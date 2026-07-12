%%% @doc In-process inbox: per-entity message delivery.
%%%
%%% The v1 broker delivers messages to entities homed on this instance in
%%% process (cross-relay PubSub is not yet reliable upstream). A message for
%%% an entity with a live receiver (an SSE `/v1/receive' connection) is pushed
%%% straight to it; otherwise it queues until the entity connects and drains
%%% the backlog. Subscribers are monitored, so a dropped connection cleans up.
-module(hecate_spartan_inbox).
-behaviour(gen_server).

-export([start_link/0, deliver/2, subscribe/1, unsubscribe/2, pending/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(st, {
    queues = #{} :: #{binary() => [map()]},      %% did => reversed msg list
    subs   = #{} :: #{binary() => [pid()]},       %% did => receiver pids
    mons   = #{} :: #{reference() => {binary(), pid()}}
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Deliver a message to an entity's inbox (push if connected, else queue).
-spec deliver(binary(), map()) -> ok.
deliver(ToDid, Msg) ->
    gen_server:cast(?MODULE, {deliver, ToDid, Msg}).

%% @doc Register the calling process as a receiver for `Did'. Returns any
%% queued backlog (and clears it); subsequent messages arrive as
%% `{spartan_msg, Msg}' to the caller.
-spec subscribe(binary()) -> [map()].
subscribe(Did) ->
    gen_server:call(?MODULE, {subscribe, Did, self()}).

-spec unsubscribe(binary(), pid()) -> ok.
unsubscribe(Did, Pid) ->
    gen_server:cast(?MODULE, {unsubscribe, Did, Pid}).

%% @doc Peek at queued (undelivered) messages for an entity, without draining.
-spec pending(binary()) -> [map()].
pending(Did) ->
    gen_server:call(?MODULE, {pending, Did}).

init([]) ->
    {ok, #st{}}.

handle_call({subscribe, Did, Pid}, _From, St) ->
    Ref = erlang:monitor(process, Pid),
    Subs = maps:update_with(Did, fun(L) -> [Pid | L] end, [Pid], St#st.subs),
    Mons = maps:put(Ref, {Did, Pid}, St#st.mons),
    Backlog = lists:reverse(maps:get(Did, St#st.queues, [])),
    Queues = maps:put(Did, [], St#st.queues),
    {reply, Backlog, St#st{subs = Subs, mons = Mons, queues = Queues}};
handle_call({pending, Did}, _From, St) ->
    {reply, lists:reverse(maps:get(Did, St#st.queues, [])), St};
handle_call(_Req, _From, St) ->
    {reply, {error, unknown_call}, St}.

handle_cast({deliver, ToDid, Msg}, St) ->
    case maps:get(ToDid, St#st.subs, []) of
        [] ->
            Q = maps:update_with(ToDid, fun(L) -> [Msg | L] end, [Msg],
                                 St#st.queues),
            {noreply, St#st{queues = Q}};
        Pids ->
            _ = [P ! {spartan_msg, Msg} || P <- Pids],
            {noreply, St}
    end;
handle_cast({unsubscribe, Did, Pid}, St) ->
    {noreply, remove_sub(Did, Pid, St)};
handle_cast(_Msg, St) ->
    {noreply, St}.

handle_info({'DOWN', Ref, process, _Pid, _Reason}, St) ->
    case maps:take(Ref, St#st.mons) of
        {{Did, Pid}, Mons2} -> {noreply, remove_sub(Did, Pid, St#st{mons = Mons2})};
        error               -> {noreply, St}
    end;
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) ->
    ok.

remove_sub(Did, Pid, St) ->
    Subs = case lists:delete(Pid, maps:get(Did, St#st.subs, [])) of
        []  -> maps:remove(Did, St#st.subs);
        Rem -> maps:put(Did, Rem, St#st.subs)
    end,
    St#st{subs = Subs}.
