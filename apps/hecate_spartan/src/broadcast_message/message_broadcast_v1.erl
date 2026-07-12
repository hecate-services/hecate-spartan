%%% @doc message_broadcast_v1 event — a message was broadcast to the realm.
-module(message_broadcast_v1).
-behaviour(evoq_event).

-export([new/1, new/4, to_map/1, from_map/1, event_type/0]).

-record(message_broadcast_v1, {
    msg_id  :: binary(),
    from    :: binary(),
    body    :: binary(),
    sent_at :: integer()
}).

-opaque message_broadcast_v1() :: #message_broadcast_v1{}.
-export_type([message_broadcast_v1/0]).

event_type() -> <<"message_broadcast_v1">>.

new(#{msg_id := M, from := F, body := B, sent_at := At}) ->
    new(M, F, B, At).

new(MsgId, From, Body, At) ->
    #message_broadcast_v1{msg_id = MsgId, from = From, body = Body, sent_at = At}.

-spec to_map(message_broadcast_v1()) -> map().
to_map(#message_broadcast_v1{msg_id = M, from = F, body = B, sent_at = At}) ->
    #{event_type => <<"message_broadcast_v1">>,
      msg_id => M, from => F, body => B, sent_at => At}.

-spec from_map(map()) -> {ok, message_broadcast_v1()} | {error, term()}.
from_map(#{msg_id := M, from := F, body := B, sent_at := At}) ->
    {ok, new(M, F, B, At)};
from_map(_) ->
    {error, invalid_message_broadcast_event}.
