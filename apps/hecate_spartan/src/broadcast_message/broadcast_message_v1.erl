%%% @doc broadcast_message_v1 command — one entity broadcasts to the realm.
-module(broadcast_message_v1).
-behaviour(evoq_command).

-export([new/1, new/4, to_map/1, from_map/1, command_type/0]).

-record(broadcast_message_v1, {
    msg_id  :: binary(),
    from    :: binary(),
    body    :: binary(),
    sent_at :: integer()
}).

-opaque broadcast_message_v1() :: #broadcast_message_v1{}.
-export_type([broadcast_message_v1/0]).

command_type() -> broadcast_message.

new(#{msg_id := M, from := F, body := B, sent_at := At}) ->
    {ok, new(M, F, B, At)};
new(_) ->
    {error, missing_fields}.

new(MsgId, From, Body, At) ->
    #broadcast_message_v1{msg_id = MsgId, from = From, body = Body, sent_at = At}.

-spec to_map(broadcast_message_v1()) -> map().
to_map(#broadcast_message_v1{msg_id = M, from = F, body = B, sent_at = At}) ->
    #{command_type => <<"broadcast_message">>,
      msg_id => M, from => F, body => B, sent_at => At}.

-spec from_map(map()) -> {ok, broadcast_message_v1()} | {error, term()}.
from_map(#{msg_id := M, from := F, body := B, sent_at := At}) ->
    {ok, new(M, F, B, At)};
from_map(_) ->
    {error, invalid_broadcast_message_command}.
