%%% @doc route_message_v1 command — one entity sends a message to another.
-module(route_message_v1).
-behaviour(evoq_command).

-export([new/1, new/5, to_map/1, from_map/1, command_type/0]).

-record(route_message_v1, {
    msg_id  :: binary(),
    from    :: binary(),
    to      :: binary(),
    body    :: binary(),
    sent_at :: integer()
}).

-opaque route_message_v1() :: #route_message_v1{}.
-export_type([route_message_v1/0]).

command_type() -> route_message.

new(#{msg_id := M, from := F, to := T, body := B, sent_at := At}) ->
    {ok, new(M, F, T, B, At)};
new(_) ->
    {error, missing_fields}.

new(MsgId, From, To, Body, At) ->
    #route_message_v1{msg_id = MsgId, from = From, to = To,
                      body = Body, sent_at = At}.

-spec to_map(route_message_v1()) -> map().
to_map(#route_message_v1{msg_id = M, from = F, to = T, body = B, sent_at = At}) ->
    #{command_type => <<"route_message">>,
      msg_id => M, from => F, to => T, body => B, sent_at => At}.

-spec from_map(map()) -> {ok, route_message_v1()} | {error, term()}.
from_map(#{msg_id := M, from := F, to := T, body := B, sent_at := At}) ->
    {ok, new(M, F, T, B, At)};
from_map(_) ->
    {error, invalid_route_message_command}.
