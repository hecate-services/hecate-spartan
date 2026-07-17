%%% @doc Handler for the route_message command.
%%%
%%% Store-free (4a): dispatch delivers DIRECTLY — into the recipient's in-process
%%% inbox when that recipient is homed here, and publishes the integration FACT to
%%% the recipient's realm inbox topic so a PEER instance can deliver to an entity
%%% homed there. No aggregate, no event store, no projection.
%%%
%%% `handle/1' + `handle_from_map/1' remain as the pure validate-and-emit step
%%% (tests, and to keep the `_v1' command/event pair honest). `fact/1' + `topic/2'
%%% are the explicit, stable public contract — NOT a bridge of the internal event.
-module(maybe_route_message).

-export([handle/1, handle_from_map/1, dispatch/1, fact/1, topic/2]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{msg_id := M, from := F, to := T, body := B} = Payload) ->
    At = maps:get(sent_at, Payload, erlang:system_time(millisecond)),
    handle(route_message_v1:new(M, F, T, B, At));
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(route_message_v1:route_message_v1()) ->
    {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{from := F, to := T, body := B} = Map = route_message_v1:to_map(Command),
    case validate(F, T, B) of
        ok ->
            Event = message_routed_v1:new(Map),
            {ok, [message_routed_v1:to_map(Event)]};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Route a message, store-free. Delivers locally if the recipient is homed
%% here, publishes the fact for a peer's home instance. Returns the legacy
%% `{ok, Seq, Events}' shape so the ingress caller is untouched.
-spec dispatch(route_message_v1:route_message_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{from := F, to := T, body := B} = Map = route_message_v1:to_map(Cmd),
    case validate(F, T, B) of
        ok ->
            Data = msg_data(Map),
            _ = deliver_if_local(Data),
            _ = publish_fact(Data),
            {ok, 0, [Data]};
        {error, _} = E ->
            E
    end.

%% @doc The public integration-fact contract for a routed message. A plain map
%% (CBOR on the wire — never JSON-encoded).
-spec fact(map()) -> map().
fact(Data) ->
    #{type    => spartan_message,
      msg_id  => gf(msg_id, Data),
      from    => gf(from, Data),
      to      => gf(to, Data),
      body    => gf(body, Data),
      sent_at => gf(sent_at, Data)}.

%% @doc Realm inbox topic for a recipient DID (realm scoping is the publish arg,
%% so the topic itself is relative).
-spec topic(binary(), binary()) -> binary().
topic(_Realm, To) ->
    <<"spartan/inbox/", To/binary>>.

%% --- Internal ---

validate(From, To, Body) ->
    case {byte_size(From), byte_size(To), byte_size(Body)} of
        {0, _, _} -> {error, from_required};
        {_, 0, _} -> {error, to_required};
        {_, _, 0} -> {error, empty_body};
        _         -> ok
    end.

msg_data(Map) ->
    maps:with([msg_id, from, to, body, sent_at], Map).

%% Deliver in-process only when the recipient is homed here. A remote recipient
%% is reached by the fact + the recipient's home federation_inbox, so delivering
%% locally would just queue junk for an entity that never connects here.
deliver_if_local(#{to := To} = Data) ->
    case hecate_spartan_entities:get(To) of
        {ok, _}            -> hecate_spartan_inbox:deliver(To, inbox_msg(Data));
        {error, not_found} -> ok
    end.

inbox_msg(#{msg_id := M, from := F, body := B, sent_at := At}) ->
    #{msg_id => M, from => F, body => B, sent_at => At}.

%% Dark is the expected degraded state: no mesh client, no realm, or the
%% hecate_om identity server not up yet (early boot). Any of these means the fact
%% stays home; a local recipient was already delivered to in-process.
publish_fact(#{to := To} = Data) ->
    try {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            catch macula:publish(Pool, Realm, topic(Realm, To), fact(Data)),
            ok;
        _DarkOrNoRealm ->
            ok
    catch _:_ ->
        ok
    end.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
