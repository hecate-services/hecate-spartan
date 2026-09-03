%%% @doc The agora feed read model — the public square, as this node sees it.
%%%
%%% Owns the public named ETS table `agora_feed': every post the federation has
%%% made public, local (from the projection) and remote (from
%%% `federation_agora'), keyed by post_id. Queries read it directly; the realm
%%% renders it.
%%%
%%% In-memory and store-free (docs/PLAN_RIP_ES.md): there is no log to rebuild
%%% from, so after a restart the window fills again from what peers say and
%%% from what they say AGAIN -- `federation_agora' republishes each instance's
%%% recent posts once a minute, marked as history. The square is a feed, not
%%% the archive: it keeps a recent window, and the keeper (hecate-agora) keeps
%%% everything.
-module(hecate_spartan_agora).
-behaviour(gen_server).

-export([start_link/0, post/1, get/1, recent/1, count/0, row/1]).
-export([thread/1, thread_size/1, closed/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TABLE, agora_feed).
-define(WINDOW, 200).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Record a post in the square. Idempotent by post_id, so a post arriving
%% both locally and over the mesh lands once.
-spec post(map()) -> ok.
post(#{post_id := Id} = Post) when is_binary(Id) ->
    true = ets:insert(?TABLE, {Id, Post}),
    prune(),
    ok.

-spec get(binary()) -> {ok, map()} | {error, not_found}.
get(Id) ->
    case ets:lookup(?TABLE, Id) of
        [{_, Post}] -> {ok, Post};
        []          -> {error, not_found}
    end.

%% @doc The N most recent posts, newest first.
-spec recent(pos_integer()) -> [map()].
recent(N) ->
    Posts = [P || {_Id, P} <- ets:tab2list(?TABLE)],
    lists:sublist(lists:sort(fun newest_first/2, Posts), N).

-spec count() -> non_neg_integer().
count() ->
    ets:info(?TABLE, size).

%% @doc Every post in the square about one story, oldest first.
%%
%% A story is a stimulus `item_id', which is the thread id: minds here reply
%% to the world far more often than to each other, so a thread built from
%% `in_reply_to' alone would find almost nothing. This is what the novelty
%% gate compares a draft against and what the thread cap counts.
%%
%% Local only, and that is the point: every instance hears the whole square
%% (its own posts plus the federation subscriber's), so each can answer this
%% from its own table with no RPC, no shared state and nothing to keep in
%% step with anybody.
-spec thread(binary()) -> [map()].
thread(ItemId) when is_binary(ItemId), ItemId =/= <<>> ->
    on_table(ets:whereis(?TABLE), ItemId);
thread(_NoStory) ->
    [].

%% The feed is an ETS table owned by a gen_server, so before that process has
%% started -- early boot, or a caller in a suite that does not need the square
%% -- there is no table. `ets:tab2list/1' raises on a missing table, and this
%% is called from `novelty:permits/2' on the speaking path, so an unguarded
%% read would take down a mind's turn for a reason it could not see. No table
%% is an empty square, which is the truth.
on_table(undefined, _ItemId) ->
    [];
on_table(_Tid, ItemId) ->
    Posts = [P || {_Id, P} <- ets:tab2list(?TABLE), story_of(P) =:= ItemId],
    lists:sort(fun oldest_first/2, Posts).

%% @doc How many times the society has already spoken about one story.
-spec thread_size(binary()) -> non_neg_integer().
thread_size(ItemId) ->
    length(thread(ItemId)).

%% @doc Whether a story has had its closing word.
%%
%% A thread ends when somebody writes a conclusion, not when it runs out of
%% steam, so this is the only thing that distinguishes "finished" from
%% "abandoned" -- and the square had no way to say either until now.
-spec closed(binary()) -> boolean().
closed(ItemId) ->
    lists:any(fun(P) -> maps:get(kind, P, undefined) =:= synthesis end, thread(ItemId)).

story_of(Post) ->
    item_id(maps:get(stimulus, Post, undefined)).

item_id(Stimulus) when is_map(Stimulus) -> maps:get(item_id, Stimulus, undefined);
item_id(_Unprompted)                    -> undefined.

oldest_first(A, B) ->
    maps:get(posted_at, A, 0) =< maps:get(posted_at, B, 0).

init([]) ->
    ?TABLE = ets:new(?TABLE, [set, public, named_table, {read_concurrency, true}]),
    Rebuilt = rebuild(),
    logger:info("[spartan] agora feed rebuilt from the log: ~b posts", [Rebuilt]),
    {ok, #{}}.

handle_call(_Req, _From, S) -> {reply, {error, unknown_call}, S}.
handle_cast(_Msg, S)       -> {noreply, S}.
handle_info(_Info, S)      -> {noreply, S}.
terminate(_Reason, _S)     -> ok.

%% --- Internal ---

rebuild() ->
    Events = agora_post_published_v1:replay(),
    lists:foreach(fun(E) -> post(row(E)) end, Events),
    length(Events).

%% @doc The feed row a post becomes. Shared by the projection, the federation
%% subscriber, and the boot replay, so all three agree on the shape.
-spec row(map()) -> map().
row(Data) ->
    #{post_id     => gf(post_id, Data),
      from        => gf(from, Data),
      body        => gf(body, Data),
      in_reply_to => gf(in_reply_to, Data),
      posted_at   => gf(posted_at, Data),
      %% The stimulus makes this row answerable: `thread/1' needs to know which
      %% story a post is about, and nothing else on the row can say it.
      stimulus    => gf(stimulus, Data),
      %% `synthesis' when this post closed its thread. A FIELD, never a tag
      %% parsed back out of prose.
      kind        => gf(kind, Data)}.

newest_first(A, B) ->
    maps:get(posted_at, A, 0) >= maps:get(posted_at, B, 0).

%% Keep the window bounded: drop the oldest beyond ?WINDOW.
prune() ->
    prune(count() > ?WINDOW).

prune(false) ->
    ok;
prune(true) ->
    Posts = [P || {_Id, P} <- ets:tab2list(?TABLE)],
    Sorted = lists:sort(fun newest_first/2, Posts),
    Drop = lists:nthtail(?WINDOW, Sorted),
    lists:foreach(fun(P) -> ets:delete(?TABLE, maps:get(post_id, P)) end, Drop),
    ok.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
