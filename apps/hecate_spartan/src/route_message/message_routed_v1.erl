%%% @doc message_routed_v1 event — a message was routed to a recipient inbox.
-module(message_routed_v1).
-behaviour(evoq_event).

-export([new/1, new/5, to_map/1, from_map/1, event_type/0]).

-record(message_routed_v1, {
    msg_id  :: binary(),
    from    :: binary(),
    to      :: binary(),
    body    :: binary(),
    sent_at :: integer()
}).

-opaque message_routed_v1() :: #message_routed_v1{}.
-export_type([message_routed_v1/0]).

event_type() -> <<"message_routed_v1">>.

new(#{msg_id := M, from := F, to := T, body := B, sent_at := At}) ->
    new(M, F, T, B, At).

new(MsgId, From, To, Body, At) ->
    #message_routed_v1{msg_id = MsgId, from = From, to = To,
                       body = Body, sent_at = At}.

-spec to_map(message_routed_v1()) -> map().
to_map(#message_routed_v1{msg_id = M, from = F, to = T, body = B, sent_at = At}) ->
    #{event_type => <<"message_routed_v1">>,
      msg_id => M, from => F, to => T, body => B, sent_at => At}.

-spec from_map(map()) -> {ok, message_routed_v1()} | {error, term()}.
from_map(#{msg_id := M, from := F, to := T, body := B, sent_at := At}) ->
    {ok, new(M, F, T, B, At)};
from_map(_) ->
    {error, invalid_message_routed_event}.
