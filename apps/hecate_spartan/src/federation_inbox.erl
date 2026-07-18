%%% @doc Federation inbox consumer.
%%%
%%% The receive side of the multi-hop mesh. Subscribes to `spartan/broadcast'
%%% once, and to `spartan/inbox/{did}' for every entity homed on THIS instance,
%%% then delivers received messages into the local inbox (`hecate_spartan_inbox')
%%% so the entity's SSE stream gets them. Only an entity's home instance is
%%% subscribed to its inbox topic, so exactly one instance delivers.
%%%
%%% Subscriptions are reconciled on a timer against the local registry, so a
%%% newly-registered entity gets a mesh inbox subscription without any coupling
%%% to the register slice, and churn self-heals. The inbox dedups by
%%% {recipient, msg_id}, so a home-instance self-loop (in-process + mesh) or a
%%% duplicate mesh delivery is dropped. Degrades safely while dark.
-module(federation_inbox).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(RECONCILE_MS, 5_000).

-record(st, {subs = #{} :: #{binary() => reference()}}). %% topic => subref

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    self() ! reconcile,
    {ok, #st{}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(reconcile, St) ->
    St2 = reconcile(St),
    erlang:send_after(?RECONCILE_MS, self(), reconcile),
    {noreply, St2};
handle_info({macula_event, _Ref, Topic, Payload, _Meta}, St) ->
    _ = deliver_event(Topic, Payload),
    {noreply, St};
handle_info({macula_event_gone, Ref, _Reason}, St) ->
    %% Drop that topic's sub; the next reconcile re-subscribes.
    Subs = maps:filter(fun(_T, R) -> R =/= Ref end, St#st.subs),
    {noreply, St#st{subs = Subs}};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

%% --- Subscription reconciliation ---

reconcile(St) ->
    reconcile_with(hecate_om:macula_client(), hecate_om_identity:realm(), St).

reconcile_with({ok, Pool}, {ok, Realm}, St) ->
    lists:foldl(fun(Topic, Acc) -> ensure_sub(Pool, Realm, Topic, Acc) end,
                St, wanted_topics());
reconcile_with(_Client, _Realm, St) ->
    St.

wanted_topics() ->
    [hecate_spartan_society:topic(<<"broadcast">>) |
        [inbox_topic(D) || #{did := D} <- hecate_spartan_entities:all(),
                           is_binary(D)]].

ensure_sub(_Pool, _Realm, Topic, St) when is_map_key(Topic, St#st.subs) ->
    St;
ensure_sub(Pool, Realm, Topic, St) ->
    case catch macula:subscribe(Pool, Realm, Topic, self()) of
        {ok, Ref} -> St#st{subs = maps:put(Topic, Ref, St#st.subs)};
        _Fail     -> St
    end.

inbox_topic(Did) -> hecate_spartan_society:inbox(Did).

%% --- Delivery ---

%% The broadcast topic is a runtime value (the society namespace), so we can't
%% pattern-match it; compare instead.
deliver_event(Topic, Payload) ->
    case Topic =:= hecate_spartan_society:topic(<<"broadcast">>) of
        true  -> deliver_broadcast(Payload);
        false -> deliver_direct(Payload)
    end.

deliver_direct(F) when is_map(F) ->
    case mget(to, F) of
        To when is_binary(To) -> hecate_spartan_inbox:deliver(To, msg_of(F));
        _NoRecipient          -> ok
    end;
deliver_direct(_) ->
    ok.

deliver_broadcast(F) when is_map(F) ->
    From = mget(from, F),
    Msg = (msg_of(F))#{broadcast => true},
    _ = [hecate_spartan_inbox:deliver(D, Msg)
         || #{did := D} <- hecate_spartan_entities:all(),
            is_binary(D), D =/= From],
    ok;
deliver_broadcast(_) ->
    ok.

msg_of(F) ->
    #{msg_id  => mget(msg_id, F),
      from    => mget(from, F),
      body    => mget(body, F),
      sent_at => mget(sent_at, F)}.

mget(AtomKey, Map) ->
    maps:get(AtomKey, Map, maps:get(atom_to_binary(AtomKey, utf8), Map, undefined)).
