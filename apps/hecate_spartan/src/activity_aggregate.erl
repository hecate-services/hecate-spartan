%%% @doc Aggregate for one reported activity.
%%%
%%% One stream per report (`act-{id}'), a single activity_reported_v1 event. No
%%% consistency boundary: the stream exists so an agent's behaviour is recorded,
%%% not just its speech. Reuses message_state (no fold).
-module(activity_aggregate).
-behaviour(evoq_aggregate).

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> message_state.

init(AggregateId) ->
    {ok, message_state:new(AggregateId)}.

-spec stream_id(binary()) -> binary().
stream_id(Id) when is_binary(Id) ->
    <<"act-", Id/binary>>.

execute(_State, #{command_type := <<"report_activity">>} = Payload) ->
    maybe_report_activity:handle_from_map(Payload);
execute(_State, _Payload) ->
    {error, unknown_command}.

apply(State, _Event) ->
    State.
