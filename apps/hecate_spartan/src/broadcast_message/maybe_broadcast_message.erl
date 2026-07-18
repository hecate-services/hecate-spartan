%%% @doc Handler for the broadcast_message command.
%%%
%%% Store-free (4a): dispatch fans out DIRECTLY to every locally-homed entity's
%%% inbox except the sender's, and publishes the spartan_broadcast fact to the
%%% realm broadcast topic so peer instances can deliver to entities homed there.
%%% No aggregate, no event store, no projection.
%%%
%%% `handle/1' + `handle_from_map/1' remain as the pure validate-and-emit step
%%% (tests, and to keep the `_v1' command/event pair honest). `fact/1' + `topic/1'
%%% are the explicit, stable public contract.
-module(maybe_broadcast_message).

-export([handle/1, handle_from_map/1, dispatch/1, fact/1, topic/1]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{msg_id := M, from := F, body := B} = Payload) ->
    At = maps:get(sent_at, Payload, erlang:system_time(millisecond)),
    handle(broadcast_message_v1:new(M, F, B, At));
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(broadcast_message_v1:broadcast_message_v1()) ->
    {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{from := F, body := B} = Map = broadcast_message_v1:to_map(Command),
    case validate(F, B) of
        ok ->
            Event = message_broadcast_v1:new(Map),
            {ok, [message_broadcast_v1:to_map(Event)]};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Broadcast, store-free. Fans out to local inboxes, publishes the fact.
%% Returns the legacy `{ok, Seq, Events}' shape so the ingress caller is untouched.
-spec dispatch(broadcast_message_v1:broadcast_message_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{from := F, body := B} = Map = broadcast_message_v1:to_map(Cmd),
    case validate(F, B) of
        ok ->
            Data = msg_data(Map),
            _ = fanout(Data),
            _ = publish_fact(Data),
            {ok, 0, [Data]};
        {error, _} = E ->
            E
    end.

%% @doc The public integration-fact contract for a broadcast. A plain map (CBOR
%% on the wire — never JSON-encoded). No `to': a broadcast is addressed to all.
-spec fact(map()) -> map().
fact(Data) ->
    #{type    => spartan_broadcast,
      msg_id  => gf(msg_id, Data),
      from    => gf(from, Data),
      body    => gf(body, Data),
      sent_at => gf(sent_at, Data)}.

-spec topic(binary()) -> binary().
topic(_Realm) ->
    hecate_spartan_society:topic(<<"broadcast">>).

%% --- Internal ---

validate(From, Body) ->
    case {byte_size(From), byte_size(Body)} of
        {0, _} -> {error, from_required};
        {_, 0} -> {error, empty_body};
        _      -> ok
    end.

msg_data(Map) ->
    maps:with([msg_id, from, body, sent_at], Map).

fanout(#{msg_id := MsgId, from := From} = Data) ->
    Msg = #{msg_id    => MsgId,
            from      => From,
            body      => gf(body, Data),
            sent_at   => gf(sent_at, Data),
            broadcast => true},
    Recipients = [maps:get(did, E) || E <- hecate_spartan_entities:all(),
                                      maps:get(did, E) =/= From],
    _ = [hecate_spartan_inbox:deliver(Did, Msg) || Did <- Recipients],
    ok.

%% Dark is the expected degraded state: no mesh client, no realm, or the
%% hecate_om identity server not up yet (early boot). Any of these means the fact
%% stays home, which is fine — local delivery already happened.
publish_fact(Data) ->
    try {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            catch macula:publish(Pool, Realm, topic(Realm), fact(Data)),
            ok;
        _DarkOrNoRealm ->
            ok
    catch _:_ ->
        ok
    end.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
