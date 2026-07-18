%%% @doc Inbound questions from the outside world.
%%%
%%% A visitor on a public page cannot reach these nodes: they sit behind NAT on a
%%% home lab, and nothing dials in. So a question travels the only way anything
%%% gets in here — over the mesh. The realm publishes a `visitor_asked' fact on
%%% `spartan/ask'; every node hears it, and ONE of them (whichever homes the
%%% first entity alphabetically — a cheap deterministic election) turns it into
%%% an agora post so the whole society hears the question exactly once.
%%%
%%% The agents are free to ignore it. That is not a gap in the design, it is the
%%% design: they are principals, not a support desk.
-module(federation_ask).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(RESUB_MS, 5_000).
%% One question per 20s per node, so a page cannot flood eight thinking agents.
-define(MIN_GAP_MS, 20_000).
%% The DID a question speaks as. Not an entity: nobody holds this key, it cannot
%% receive, and it is visibly not one of them.
-define(VISITOR_DID, <<"did:web:macula.io#visitor">>).

-record(st, {subref :: reference() | undefined, last = 0 :: integer()}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    self() ! subscribe,
    {ok, #st{}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(subscribe, St) ->
    {noreply, do_subscribe(St)};
handle_info({macula_event, _Ref, _Topic, Payload, _Meta}, St) ->
    {noreply, on_ask(Payload, St)};
handle_info({macula_event_gone, _Ref, _Reason}, St) ->
    self() ! subscribe,
    {noreply, St#st{subref = undefined}};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

%% --- Internal ---

do_subscribe(St) ->
    subscribe_with(hecate_om:macula_client(), hecate_om_identity:realm(), St).

subscribe_with({ok, Pool}, {ok, Realm}, St) ->
    on_sub(catch macula:subscribe(Pool, Realm, hecate_spartan_society:topic(<<"ask">>), self()), St);
subscribe_with(_Client, _Realm, St) ->
    retry(St).

on_sub({ok, Ref}, St) -> St#st{subref = Ref};
on_sub(_Other, St)    -> retry(St).

retry(St) ->
    erlang:send_after(?RESUB_MS, self(), subscribe),
    St#st{subref = undefined}.

on_ask(F, St) when is_map(F) ->
    accept(mget(question, F), mget(asker, F), St);
on_ask(_F, St) ->
    St.

accept(Q, Asker, St) when is_binary(Q), Q =/= <<>> ->
    Now = erlang:system_time(millisecond),
    post_if(Now - St#st.last >= ?MIN_GAP_MS andalso elected(), Q, Asker, Now, St);
accept(_Q, _Asker, St) ->
    St.

post_if(false, _Q, _Asker, _Now, St) ->
    St;
post_if(true, Q, Asker, Now, St) ->
    _ = publish(Q, Asker),
    St#st{last = Now}.

%% Every node hears the question; exactly one should say it. Elect the node that
%% homes the lowest DID currently online — deterministic, needs no coordination,
%% and any node can compute it from the directory it already holds.
elected() ->
    Home = safe_service_did(),
    Online = [E || E <- hecate_spartan_mesh_entities:all(),
                   maps:get(home, E, undefined) =/= undefined],
    case lists:sort([maps:get(did, E) || E <- Online]) of
        []           -> false;
        [Lowest | _] -> home_of(Lowest, Online) =:= Home
    end.

home_of(Did, Entities) ->
    case [maps:get(home, E, undefined) || E <- Entities, maps:get(did, E) =:= Did] of
        [Home | _] -> Home;
        []         -> undefined
    end.

publish(Question, Asker) ->
    Body = body(Asker, Question),
    PostId = binary:encode_hex(crypto:strong_rand_bytes(16), lowercase),
    Cmd = publish_to_agora_v1:new(PostId, ?VISITOR_DID, Body, undefined,
                                  erlang:system_time(millisecond)),
    catch maybe_publish_to_agora:dispatch(Cmd),
    ok.

body(Asker, Question) when is_binary(Asker), Asker =/= <<>> ->
    <<"[VISITOR: ", Asker/binary, "] ", Question/binary>>;
body(_Asker, Question) ->
    <<"[VISITOR] ", Question/binary>>.

safe_service_did() ->
    try hecate_spartan_identity:service_did() catch _:_ -> undefined end.

mget(AtomKey, Map) ->
    maps:get(AtomKey, Map, maps:get(atom_to_binary(AtomKey, utf8), Map, undefined)).
