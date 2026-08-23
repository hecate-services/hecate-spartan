%%% @doc Configures macula_rag once hecate_om has a mesh client, so every
%%% mind on this node can call macula_rag:query/2 — the transport behind the
%%% rag_search L2 capability (mind_capabilities.erl, mind_tools.erl).
%%%
%%% This node is a RAG CONSUMER only. Unlike hecate-rag's own federation
%%% wiring (hecate_rag_federation.erl in that repo), nothing here registers a
%%% responder or advertises a shard: a Spartan mind has no corpus of its own
%%% to answer queries against, only a granted right to ask others'.
%%%
%%% Retries every ?RETRY_MS until hecate_om is configured, same shape as
%%% federation_registry.erl's do_subscribe/1 retry.
-module(federation_rag).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(RETRY_MS, 2_000).

-record(st, {configured = false :: boolean()}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    self() ! try_configure,
    {ok, #st{}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(try_configure, #st{configured = true} = St) ->
    {noreply, St};
handle_info(try_configure, St) ->
    St1 = maybe_configure(St),
    schedule_retry_if_incomplete(St1),
    {noreply, St1};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

%%% Internal

maybe_configure(St) ->
    on_ready({hecate_om:macula_client(), hecate_om_identity:realm()}, St).

on_ready({{ok, Pool}, {ok, Realm}}, St) ->
    on_configured(safe_configure(Pool, Realm), St);
on_ready(_NotReady, St) ->
    St.

on_configured(ok, St) ->
    logger:info("[federation_rag] macula_rag configured"),
    St#st{configured = true};
on_configured({error, Reason}, St) ->
    logger:warning("[federation_rag] configure failed: ~p", [Reason]),
    St.

%% try/catch is warranted here (an accepted deviation, not the default): it
%% turns an unreachable/misconfigured macula_rag into a logged retry instead
%% of taking this node's whole supervision tree down.
safe_configure(Pool, Realm) ->
    try
        ok = macula_rag:configure(Pool, Realm),
        ok
    catch C:R -> {error, {C, R}}
    end.

schedule_retry_if_incomplete(#st{configured = true}) ->
    ok;
schedule_retry_if_incomplete(_St) ->
    erlang:send_after(?RETRY_MS, self(), try_configure),
    ok.
