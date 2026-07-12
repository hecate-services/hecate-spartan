%%% @doc Process manager: on message_broadcast_v1, publish an integration FACT
%%% to the realm broadcast topic. The federation seam for broadcasts — see
%%% on_message_routed_publish_fact for the rationale. Degrades safely when dark.
-module(on_message_broadcast_publish_fact).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4, fact/1, topic/1]).

-define(TABLE, broadcast_fact_checkpoint).

interested_in() ->
    [<<"message_broadcast_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => ?TABLE}),
    {ok, #{}, RM}.

project(#{data := Data} = Event, _Metadata, State, RM) ->
    case get_event_type(Event) of
        <<"message_broadcast_v1">> ->
            _ = publish_fact(Data),
            {ok, RM2} = evoq_read_model:put(gf(msg_id, Data), published, RM),
            {ok, State, RM2};
        _ ->
            {ok, State, RM}
    end;
project(_Event, _Metadata, State, RM) ->
    {ok, State, RM}.

-spec fact(map()) -> map().
fact(Data) ->
    #{type    => spartan_broadcast,
      msg_id  => gf(msg_id, Data),
      from    => gf(from, Data),
      body    => gf(body, Data),
      sent_at => gf(sent_at, Data)}.

-spec topic(binary()) -> binary().
topic(_Realm) ->
    <<"spartan/broadcast">>.

%% --- Internal ---

publish_fact(Data) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            catch macula:publish(Pool, Realm, topic(Realm), fact(Data)),
            ok;
        _DarkOrNoRealm ->
            ok
    end.

get_event_type(#{event_type := T}) -> T;
get_event_type(_)                  -> undefined.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
