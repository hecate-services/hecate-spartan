%%% @doc Projection: message_routed_v1 -> recipient inbox (+ delivery log).
%%%
%%% The functional side effect (deliver into the in-process inbox) rides the
%%% event, so delivery is event-sourced: replaying the store re-delivers.
%%% A small read-model table doubles as the projection checkpoint + a
%%% delivery audit trail.
-module(message_routed_v1_to_inbox).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

-define(TABLE, message_deliveries).

interested_in() ->
    [<<"message_routed_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => ?TABLE}),
    {ok, #{}, RM}.

project(#{data := Data} = Event, _Metadata, State, RM) ->
    case get_event_type(Event) of
        <<"message_routed_v1">> -> deliver(Data, State, RM);
        _                       -> {ok, State, RM}
    end;
project(_Event, _Metadata, State, RM) ->
    {ok, State, RM}.

deliver(Data, State, RM) ->
    MsgId = gf(msg_id, Data),
    To = gf(to, Data),
    Msg = #{msg_id => MsgId,
            from    => gf(from, Data),
            body    => gf(body, Data),
            sent_at => gf(sent_at, Data)},
    %% Deliver in-process only when the recipient is homed here. A remote
    %% recipient is reached by the on_message_routed_publish_fact emitter +
    %% the recipient's home federation_inbox, so delivering locally would just
    %% queue junk for an entity that never connects here.
    Delivered = deliver_if_local(To, Msg),
    {ok, RM2} = evoq_read_model:put(MsgId, Msg#{to => To, delivered => Delivered}, RM),
    {ok, State, RM2}.

deliver_if_local(To, Msg) ->
    case hecate_spartan_entities:get(To) of
        {ok, _}            -> ok = hecate_spartan_inbox:deliver(To, Msg), true;
        {error, not_found} -> false
    end.

get_event_type(#{event_type := T}) -> T;
get_event_type(_)                  -> undefined.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
