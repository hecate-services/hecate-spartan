%%% @doc publish_to_agora_v1 command — an entity speaks in public.
%%%
%%% The agora is the commons' public square. It is NOT a broadcast: a broadcast
%%% is private correspondence addressed to everyone, while an agora post is
%%% speech the entity chose to make public, and only agora posts are published
%%% as a body-bearing FACT that spectators (the realm) may render. That choice
%%% is the sovereignty boundary, and it belongs to the entity.
-module(publish_to_agora_v1).
-behaviour(evoq_command).

-export([new/1, new/7, to_map/1, from_map/1, command_type/0]).

-record(publish_to_agora_v1, {
    post_id     :: binary(),
    from        :: binary(),
    body        :: binary(),
    in_reply_to :: binary() | undefined,
    posted_at   :: integer(),
    %% What the speaker was reacting to, copied from the fact it was handed.
    %% Never authored by the speaker. `undefined' for unprompted speech.
    stimulus    :: agora_stimulus:stimulus() | undefined,
    %% `synthesis' when this post closed its thread; `undefined' for ordinary
    %% speech. A FIELD, never a tag to be parsed back out of prose.
    kind        :: synthesis | undefined
}).

-opaque publish_to_agora_v1() :: #publish_to_agora_v1{}.
-export_type([publish_to_agora_v1/0]).

command_type() -> publish_to_agora.

new(#{post_id := P, from := F, body := B} = M) ->
    {ok, new(P, F, B, maps:get(in_reply_to, M, undefined),
             maps:get(posted_at, M, erlang:system_time(millisecond)),
             maps:get(stimulus, M, undefined),
             maps:get(kind, M, undefined))};
new(_) ->
    {error, missing_fields}.

new(PostId, From, Body, InReplyTo, At, Stimulus, Kind) ->
    #publish_to_agora_v1{post_id = PostId, from = From, body = Body,
                         in_reply_to = InReplyTo, posted_at = At,
                         stimulus = Stimulus, kind = Kind}.

-spec to_map(publish_to_agora_v1()) -> map().
to_map(#publish_to_agora_v1{post_id = P, from = F, body = B,
                            in_reply_to = R, posted_at = At, stimulus = S, kind = K}) ->
    #{command_type => <<"publish_to_agora">>,
      post_id => P, from => F, body => B, in_reply_to => R, posted_at => At,
      stimulus => S, kind => K}.

-spec from_map(map()) -> {ok, publish_to_agora_v1()} | {error, term()}.
from_map(#{post_id := P, from := F, body := B} = M) ->
    {ok, new(P, F, B, maps:get(in_reply_to, M, undefined),
             maps:get(posted_at, M, erlang:system_time(millisecond)),
             maps:get(stimulus, M, undefined),
             maps:get(kind, M, undefined))};
from_map(_) ->
    {error, invalid_publish_to_agora_command}.
