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
-export([online/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(st, {
    queues = #{} :: #{binary() => [map()]},      %% did => reversed msg list
    subs   = #{} :: #{binary() => [pid()]},       %% did => receiver pids
    mons   = #{} :: #{reference() => {binary(), pid()}},
    seen   = #{} :: #{{binary(), binary()} => true} %% {did, msg_id} delivered
}).

%% Bound on the dedup set before a crude flush (per-recipient msg_id keys).
-define(SEEN_MAX, 20000).

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

%% @doc Is this entity actually HOME? True when it holds an open receive stream.
%%
%% Presence, not registration. The registry records every entity that ever
%% registered and never forgets one; a mind that is running holds an SSE stream
%% open through its bridge for as long as it lives. That stream is the only
%% honest answer to "is anybody there".
-spec online(binary()) -> boolean().
online(Did) ->
    gen_server:call(?MODULE, {online, Did}).

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
handle_call({online, Did}, _From, St) ->
    {reply, maps:get(Did, St#st.subs, []) =/= [], St};
handle_call(_Req, _From, St) ->
    {reply, {error, unknown_call}, St}.

handle_cast({deliver, ToDid, Msg}, St) ->
    MsgId = maps:get(msg_id, Msg, undefined),
    case is_dup(ToDid, MsgId, St) of
        true  -> {noreply, St};
        false -> {noreply, do_deliver(ToDid, Msg, mark_seen(ToDid, MsgId, St))}
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

do_deliver(ToDid, Msg, St) ->
    dispatch(maps:get(ToDid, St#st.subs, []), ToDid, Msg, St).

dispatch([], ToDid, Msg, St) ->
    St#st{queues = enqueue(ToDid, Msg, St#st.queues)};
dispatch(Pids, _ToDid, Msg, St) ->
    _ = [P ! {spartan_msg, Msg} || P <- Pids],
    St.

enqueue(ToDid, Msg, Queues) ->
    maps:update_with(ToDid, fun(L) -> [Msg | L] end, [Msg], Queues).

%% Dedup keyed per recipient, so a broadcast (one msg_id, many recipients)
%% still fans out, while a duplicate to the same recipient is dropped.
is_dup(ToDid, MsgId, St) when is_binary(MsgId) ->
    maps:is_key({ToDid, MsgId}, St#st.seen);
is_dup(_ToDid, _MsgId, _St) ->
    false.

mark_seen(ToDid, MsgId, St) when is_binary(MsgId) ->
    Seen0 = case map_size(St#st.seen) >= ?SEEN_MAX of
        true  -> #{};
        false -> St#st.seen
    end,
    St#st{seen = maps:put({ToDid, MsgId}, true, Seen0)};
mark_seen(_ToDid, _MsgId, St) ->
    St.

remove_sub(Did, Pid, St) ->
    Subs = case lists:delete(Pid, maps:get(Did, St#st.subs, [])) of
        []  -> maps:remove(Did, St#st.subs);
        Rem -> maps:put(Did, Rem, St#st.subs)
    end,
    St#st{subs = Subs}.
