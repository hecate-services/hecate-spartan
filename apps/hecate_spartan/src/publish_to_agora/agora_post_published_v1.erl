%%% @doc agora_post_published_v1 event — an entity said something in public.
-module(agora_post_published_v1).
-behaviour(evoq_event).

-export([new/1, new/5, to_map/1, from_map/1, event_type/0]).
-export([replay/0]).

%% The square is a feed, not an archive: the read model holds a recent window
%% and the log holds the rest.
-define(REPLAY_BATCH, 500).

-record(agora_post_published_v1, {
    post_id     :: binary(),
    from        :: binary(),
    body        :: binary(),
    in_reply_to :: binary() | undefined,
    posted_at   :: integer()
}).

-opaque agora_post_published_v1() :: #agora_post_published_v1{}.
-export_type([agora_post_published_v1/0]).

event_type() -> <<"agora_post_published_v1">>.

new(#{post_id := P, from := F, body := B} = M) ->
    new(P, F, B, maps:get(in_reply_to, M, undefined),
        maps:get(posted_at, M, erlang:system_time(millisecond))).

new(PostId, From, Body, InReplyTo, At) ->
    #agora_post_published_v1{post_id = PostId, from = From, body = Body,
                             in_reply_to = InReplyTo, posted_at = At}.

-spec to_map(agora_post_published_v1()) -> map().
to_map(#agora_post_published_v1{post_id = P, from = F, body = B,
                                in_reply_to = R, posted_at = At}) ->
    #{event_type => <<"agora_post_published_v1">>,
      post_id => P, from => F, body => B, in_reply_to => R, posted_at => At}.

-spec from_map(map()) -> {ok, agora_post_published_v1()} | {error, term()}.
from_map(#{post_id := P, from := F, body := B} = M) ->
    {ok, new(P, F, B, maps:get(in_reply_to, M, undefined),
             maps:get(posted_at, M, erlang:system_time(millisecond)))};
from_map(_) ->
    {error, invalid_agora_post_published_event}.

%% @doc This instance's own agora posts, oldest first, flattened to event maps.
%%
%% The feed read model replays these at boot for the same reason the registries
%% do: evoq's store subscription replays the log once, at store start, which
%% `hecate_om:boot/1' performs before the supervision tree exists, so no
%% projection is registered to hear it. Peers' posts return via the federation
%% subscriber, not from here.
-spec replay() -> [map()].
replay() ->
    replay_from(application:get_env(hecate_spartan, event_store_id)).

replay_from(undefined) ->
    [];
replay_from({ok, StoreId}) ->
    case catch evoq_event_store:read_events_by_types(
                 StoreId, [event_type()], ?REPLAY_BATCH) of
        {ok, Events} when is_list(Events) -> Events;
        _Unavailable                      -> []
    end.
