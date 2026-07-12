%%% @doc Ingress: content-addressed attachments over the mesh.
%%%
%%%   POST /v1/artifact          — body = raw bytes -> macula content -> hash
%%%   GET  /v1/artifact/:hash    — hash -> bytes
%%%
%%% Content lives in the Macula mesh (content-addressed), not locally; the hash
%%% is the provenance. When no mesh client is attached (offline / no station),
%%% the endpoints return 503 rather than blocking. POST needs the content/share
%%% cap; GET needs any valid UCAN.
-module(artifact_api).

-export([init/2, decode_mcid/1]).

-dialyzer({nowarn_function, [put_content/2, get_content/2]}).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_put(Req0, State);
        <<"GET">>  -> handle_get(Req0, State);
        _          -> json(405, #{error => method_not_allowed}, Req0, State)
    end.

%% --- POST /v1/artifact ---
handle_put(Req0, State) ->
    case hecate_spartan_auth:authenticate(Req0) of
        {ok, _Did, Payload} ->
            case hecate_spartan_auth:has_cap(Payload, <<"content/share">>) of
                true  -> put_content(Req0, State);
                false -> json(403, #{error => missing_share_cap}, Req0, State)
            end;
        {error, Reason} ->
            json(401, #{error => Reason}, Req0, State)
    end.

put_content(Req0, State) ->
    case hecate_om:macula_client() of
        {ok, Pool} ->
            {ok, Bytes, Req1} = read_body(Req0, <<>>),
            case macula:put_content(Pool, Bytes) of
                {ok, MCID} ->
                    json(200, #{hash => binary:encode_hex(MCID, lowercase),
                                size => byte_size(Bytes)}, Req1, State);
                {error, R} ->
                    json(502, #{error => put_failed, reason => fmt(R)}, Req1, State)
            end;
        {error, _} ->
            json(503, #{error => mesh_unavailable}, Req0, State)
    end.

%% --- GET /v1/artifact/:hash ---
handle_get(Req0, State) ->
    case hecate_spartan_auth:authenticate(Req0) of
        {ok, _Did, _Payload} ->
            case decode_mcid(cowboy_req:binding(hash, Req0)) of
                {ok, MCID} -> get_content(MCID, Req0);
                error      -> json(400, #{error => invalid_hash}, Req0, State)
            end;
        {error, Reason} ->
            json(401, #{error => Reason}, Req0, State)
    end.

get_content(MCID, Req0) ->
    case hecate_om:macula_client() of
        {ok, Pool} ->
            case macula:get_content(Pool, MCID) of
                {ok, Bin} ->
                    Req = cowboy_req:reply(200,
                        #{<<"content-type">> => <<"application/octet-stream">>},
                        Bin, Req0),
                    {ok, Req, #{}};
                {error, not_found} ->
                    json(404, #{error => not_found}, Req0, #{});
                {error, R} ->
                    json(502, #{error => get_failed, reason => fmt(R)}, Req0, #{})
            end;
        {error, _} ->
            json(503, #{error => mesh_unavailable}, Req0, #{})
    end.

%% @doc Decode a hex hash back into a Macula content id, validating its shape
%% (`<<1, 16#55, Hash:32/binary>>'). Pure — safe to unit test.
-spec decode_mcid(binary() | undefined) -> {ok, binary()} | error.
decode_mcid(undefined) ->
    error;
decode_mcid(Hex) when is_binary(Hex) ->
    try binary:decode_hex(Hex) of
        <<1, 16#55, _:32/binary>> = MCID -> {ok, MCID};
        _                                -> error
    catch _:_ ->
        error
    end.

%% --- Internal ---

read_body(Req0, Acc) ->
    case cowboy_req:read_body(Req0) of
        {ok, Data, Req1}   -> {ok, <<Acc/binary, Data/binary>>, Req1};
        {more, Data, Req1} -> read_body(Req1, <<Acc/binary, Data/binary>>)
    end.

json(Code, Map, Req0, State) ->
    Req = cowboy_req:reply(Code,
                           #{<<"content-type">> => <<"application/json">>},
                           jsx:encode(Map), Req0),
    {ok, Req, State}.

fmt(T) -> iolist_to_binary(io_lib:format("~p", [T])).
