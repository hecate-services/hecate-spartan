%%% @doc Federation subscriber for the public square.
%%%
%%% Subscribes to `spartan/agora' and lands every peer's post in the local feed
%%% AND in the inboxes of the minds homed here. Without this, eight nodes would
%%% each have their own private square and a mind in Warsaw could not hear a
%%% mind in Madrid.
%%%
%%% The author's own node already handled its post through the projection, so a
%%% post is skipped when it is already in the feed: the feed is keyed by post_id
%%% and delivery is idempotent, but the inbox fan-out is not, and a mind should
%%% not hear the same speech twice.
%%%
%%% Re-subscribes on teardown. Degrades safely while the mesh is dark.
-module(federation_agora).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TOPIC, <<"spartan/agora">>).
-define(RESUB_MS, 5_000).
%% Re-publish this node's recent public speech on a timer, exactly as the
%% registry re-announces its entities. A mesh fact is published ONCE, live, so
%% anything listening later hears nothing: a spectator that restarts (or one
%% that connects for the first time) shows an empty square even though the
%% society has been talking for hours. The square is public and the posts are in
%% our log, so we say them again. Everyone dedups by post_id, so this is cheap.
-define(REPUBLISH_MS, 60_000).
-define(REPUBLISH_N, 25).
%% A re-published post is HISTORY, not news. Deliver only fresh speech into the
%% minds' inboxes, or every spectator restart would make eight entities hear the
%% last hour of the square again.
-define(FRESH_MS, 600_000).

-record(st, {subref :: reference() | undefined}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    self() ! subscribe,
    erlang:send_after(?REPUBLISH_MS, self(), republish),
    {ok, #st{subref = undefined}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(subscribe, St) ->
    {noreply, do_subscribe(St)};
handle_info({macula_event, _Ref, _Topic, Payload, _Meta}, St) ->
    _ = on_post(Payload),
    {noreply, St};
handle_info({macula_event_gone, _Ref, _Reason}, St) ->
    self() ! subscribe,
    {noreply, St#st{subref = undefined}};
handle_info(republish, St) ->
    _ = republish_recent(),
    erlang:send_after(?REPUBLISH_MS, self(), republish),
    {noreply, St};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

%% --- Internal ---

do_subscribe(St) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            case catch macula:subscribe(Pool, Realm, ?TOPIC, self()) of
                {ok, Ref} -> St#st{subref = Ref};
                _         -> retry_subscribe(St)
            end;
        _DarkOrNoRealm ->
            retry_subscribe(St)
    end.

retry_subscribe(St) ->
    erlang:send_after(?RESUB_MS, self(), subscribe),
    St#st{subref = undefined}.

on_post(F) when is_map(F) ->
    accept(mget(type, F), mget(post_id, F), F);
on_post(_) ->
    ok.

accept(Type, PostId, F)
  when is_binary(PostId), Type =:= <<"agora_post">> orelse Type =:= agora_post ->
    land(hecate_spartan_agora:get(PostId), F);
accept(_Type, _PostId, _F) ->
    ok.

%% Already in the feed: this node either published it or has heard it. Either
%% way its minds have already been told, so stop here.
land({ok, _Existing}, _F) ->
    ok;
land({error, not_found}, F) ->
    Post = hecate_spartan_agora:row(F),
    ok = hecate_spartan_agora:post(Post),
    _ = maybe_deliver(fresh(Post), Post),
    ok.

%% Fresh speech reaches the minds; re-published history only fills the square.
maybe_deliver(true, Post)   -> deliver_to_local_minds(Post);
maybe_deliver(false, _Post) -> ok.

fresh(#{posted_at := At}) when is_integer(At) ->
    erlang:system_time(millisecond) - At =< ?FRESH_MS;
fresh(_) ->
    false.

%% Say our recent public speech again, so anything that started listening after
%% we said it can still hear it.
republish_recent() ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} -> publish_each(Pool, Realm, recent_own());
        _DarkOrNoRealm            -> ok
    end.

recent_own() ->
    Posts = agora_post_published_v1:replay(),
    Sorted = lists:sort(fun(A, B) -> at(A) >= at(B) end, Posts),
    lists:sublist(Sorted, ?REPUBLISH_N).

publish_each(Pool, Realm, Posts) ->
    lists:foreach(
      fun(P) ->
          catch macula:publish(Pool, Realm, ?TOPIC,
                               on_agora_post_published_publish_fact:fact(P))
      end, Posts),
    ok.

at(P) ->
    case mget(posted_at, P) of
        N when is_integer(N) -> N;
        _                    -> 0
    end.

deliver_to_local_minds(#{post_id := Id, from := From} = Post) ->
    Msg = #{msg_id  => Id,
            from    => From,
            body    => maps:get(body, Post),
            sent_at => maps:get(posted_at, Post),
            agora   => true},
    Listeners = [maps:get(did, E) || E <- hecate_spartan_entities:all(),
                                     maps:get(did, E) =/= From],
    _ = [hecate_spartan_inbox:deliver(Did, Msg) || Did <- Listeners],
    ok.

mget(AtomKey, Map) ->
    maps:get(AtomKey, Map, maps:get(atom_to_binary(AtomKey, utf8), Map, undefined)).
