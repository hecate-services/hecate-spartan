%%% @doc The agora feed read model — the public square, as this node sees it.
%%%
%%% Owns the public named ETS table `agora_feed': every post the federation has
%%% made public, local (from the projection) and remote (from
%%% `federation_agora'), keyed by post_id. Queries read it directly; the realm
%%% renders it.
%%%
%%% In-memory, so it rebuilds this node's OWN posts from the log at boot (see
%%% `agora_post_published_v1:replay/0'); peers' posts return as they re-arrive
%%% on the mesh. The square is a feed, not the archive: it keeps a recent window
%%% and the event log keeps everything, which is the point of recording public
%%% speech as events in the first place.
-module(hecate_spartan_agora).
-behaviour(gen_server).

-export([start_link/0, post/1, get/1, recent/1, count/0, row/1]).
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
      posted_at   => gf(posted_at, Data)}.

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
