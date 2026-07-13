%%% @doc Process manager: on activity_reported_v1, publish it to the mesh.
%%%
%%% This is what makes an autonomous agent legible. Messages are sparse: an
%%% agent may think for minutes between them, and to anything watching it looks
%%% dead. The activity stream is the pulse — the action it took, the thought it
%%% had, the model call it made — published as a fact so any spectator can watch
%%% the society work, not just hear it talk.
-module(on_activity_reported_publish_fact).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4, fact/1, topic/0]).

-define(TABLE, activity_fact_checkpoint).

interested_in() ->
    [<<"activity_reported_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => ?TABLE}),
    {ok, #{}, RM}.

project(#{data := Data} = Event, _Metadata, State, RM) ->
    case get_event_type(Event) of
        <<"activity_reported_v1">> ->
            _ = publish_fact(Data),
            {ok, RM2} = evoq_read_model:put(gf(activity_id, Data), published, RM),
            {ok, State, RM2};
        _ ->
            {ok, State, RM}
    end;
project(_Event, _Metadata, State, RM) ->
    {ok, State, RM}.

-spec topic() -> binary().
topic() -> <<"spartan/activity">>.

-spec fact(map()) -> map().
fact(Data) ->
    #{type        => spartan_activity,
      activity_id => gf(activity_id, Data),
      did         => gf(did, Data),
      kind        => gf(kind, Data),
      summary     => gf(summary, Data),
      at          => gf(at, Data),
      locale      => hecate_spartan_service:locale()}.

publish_fact(Data) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            catch macula:publish(Pool, Realm, topic(), fact(Data)),
            ok;
        _DarkOrNoRealm ->
            ok
    end.

get_event_type(#{event_type := T}) -> T;
get_event_type(_)                  -> undefined.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
