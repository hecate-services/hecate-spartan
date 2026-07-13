%%% @doc Aggregate for one agora post.
%%%
%%% One stream per post (`post-{id}'), a single agora_post_published_v1 event.
%%% Like a message, a post carries no consistency boundary; the stream exists so
%%% that public speech is an event (provenance, and right-to-erasure over what
%%% an entity said in public). No folding. Reuses message_state, which is the
%%% same trivial no-fold state.
-module(agora_aggregate).
-behaviour(evoq_aggregate).

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> message_state.

init(AggregateId) ->
    {ok, message_state:new(AggregateId)}.

%% The post id is a 32-char hex token minted at the ingress.
-spec stream_id(binary()) -> binary().
stream_id(PostId) when is_binary(PostId) ->
    <<"post-", PostId/binary>>.

execute(_State, #{command_type := <<"publish_to_agora">>} = Payload) ->
    maybe_publish_to_agora:handle_from_map(Payload);
execute(_State, _Payload) ->
    {error, unknown_command}.

apply(State, _Event) ->
    State.
