%%% @doc Projection: message_broadcast_v1 -> every registered entity's inbox
%%% (except the sender). Fan-out delivery is event-sourced, same as routing.
-module(message_broadcast_v1_to_inboxes).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

-define(TABLE, broadcast_deliveries).

interested_in() ->
    [<<"message_broadcast_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => ?TABLE}),
    {ok, #{}, RM}.

project(#{data := Data} = Event, _Metadata, State, RM) ->
    case get_event_type(Event) of
        <<"message_broadcast_v1">> -> fanout(Data, State, RM);
        _                          -> {ok, State, RM}
    end;
project(_Event, _Metadata, State, RM) ->
    {ok, State, RM}.

fanout(Data, State, RM) ->
    From = gf(from, Data),
    MsgId = gf(msg_id, Data),
    Msg = #{msg_id    => MsgId,
            from      => From,
            body      => gf(body, Data),
            sent_at   => gf(sent_at, Data),
            broadcast => true},
    Recipients = [maps:get(did, E) || E <- hecate_spartan_entities:all(),
                                      maps:get(did, E) =/= From],
    _ = [hecate_spartan_inbox:deliver(Did, Msg) || Did <- Recipients],
    {ok, RM2} = evoq_read_model:put(MsgId,
                                    Msg#{recipients => length(Recipients)}, RM),
    {ok, State, RM2}.

get_event_type(#{event_type := T}) -> T;
get_event_type(_)                  -> undefined.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
