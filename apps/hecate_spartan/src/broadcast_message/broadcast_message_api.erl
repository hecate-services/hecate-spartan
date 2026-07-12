%%% @doc Ingress: POST /v1/broadcast — send a message to the whole realm.
%%%
%%% Sender authenticates with its UCAN (msg/send cap). Body: { "body": "..." }.
-module(broadcast_message_api).

-export([init/2]).

-dialyzer({nowarn_function, [do_broadcast/3]}).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_post(Req0, State);
        _          -> reply(405, #{error => method_not_allowed}, Req0, State)
    end.

handle_post(Req0, State) ->
    case hecate_spartan_auth:authenticate(Req0) of
        {ok, From, Payload} ->
            case hecate_spartan_auth:has_cap(Payload, <<"msg/send">>) of
                true  -> read_and_broadcast(From, Req0, State);
                false -> reply(403, #{error => missing_send_cap}, Req0, State)
            end;
        {error, Reason} ->
            reply(401, #{error => Reason}, Req0, State)
    end.

read_and_broadcast(From, Req0, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    case decode(Body) of
        {ok, #{<<"body">> := Text}} when is_binary(Text), Text =/= <<>> ->
            do_broadcast(From, Text, Req1);
        _ ->
            reply(400, #{error => invalid_request}, Req1, State)
    end.

do_broadcast(From, Text, Req) ->
    MsgId = binary:encode_hex(crypto:strong_rand_bytes(16), lowercase),
    Cmd = broadcast_message_v1:new(MsgId, From, Text,
                                   erlang:system_time(millisecond)),
    case maybe_broadcast_message:dispatch(Cmd) of
        {ok, _V, _E} ->
            reply(202, #{msg_id => MsgId, status => <<"broadcast">>}, Req, #{});
        {error, Reason} ->
            reply(500, #{error => dispatch_failed, reason => fmt(Reason)}, Req, #{})
    end.

decode(Body) ->
    try {ok, jsx:decode(Body, [return_maps])} catch _:_ -> {error, bad_json} end.

reply(Code, Map, Req0, State) ->
    Req = cowboy_req:reply(Code,
                           #{<<"content-type">> => <<"application/json">>},
                           jsx:encode(Map), Req0),
    {ok, Req, State}.

fmt(T) -> iolist_to_binary(io_lib:format("~p", [T])).
