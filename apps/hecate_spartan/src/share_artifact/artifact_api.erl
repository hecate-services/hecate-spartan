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

-dialyzer({nowarn_function, [put_content/3, fetch/3, served/2]}).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_put(Req0, State);
        <<"GET">>  -> handle_get(Req0, State);
        _          -> json(405, #{error => method_not_allowed}, Req0, State)
    end.

%% --- POST /v1/artifact ---
handle_put(Req0, State) ->
    put_authed(hecate_spartan_auth:authenticate(Req0), Req0, State).

put_authed({ok, _Did, Payload}, Req0, State) ->
    put_gate(hecate_spartan_auth:has_cap(Payload, <<"content/share">>), Req0, State);
put_authed({error, Reason}, Req0, State) ->
    json(401, #{error => Reason}, Req0, State).

put_gate(true, Req0, State)   -> put_content(hecate_om:macula_client(), Req0, State);
put_gate(false, Req0, State)  -> json(403, #{error => missing_share_cap}, Req0, State).

put_content({ok, Pool}, Req0, State) ->
    {ok, Bytes, Req1} = read_body(Req0, <<>>),
    put_result(macula:put_content(Pool, Bytes), Bytes, Req1, State);
put_content({error, _}, Req0, State) ->
    json(503, #{error => mesh_unavailable}, Req0, State).

put_result({ok, MCID}, Bytes, Req, State) ->
    json(200, #{hash => binary:encode_hex(MCID, lowercase),
                size => byte_size(Bytes)}, Req, State);
put_result({error, R}, _Bytes, Req, State) ->
    json(502, #{error => put_failed, reason => fmt(R)}, Req, State).

%% --- GET /v1/artifact/:hash ---
handle_get(Req0, State) ->
    get_authed(hecate_spartan_auth:authenticate(Req0), Req0, State).

get_authed({ok, _Did, _Payload}, Req0, State) ->
    get_decoded(decode_mcid(cowboy_req:binding(hash, Req0)), Req0, State);
get_authed({error, Reason}, Req0, State) ->
    json(401, #{error => Reason}, Req0, State).

get_decoded({ok, MCID}, Req0, _State) -> get_content(MCID, Req0);
get_decoded(error, Req0, State)       -> json(400, #{error => invalid_hash}, Req0, State).

get_content(MCID, Req0) ->
    fetch(hecate_om:macula_client(), MCID, Req0).

fetch({ok, Pool}, MCID, Req0) ->
    served(macula:get_content(Pool, MCID), Req0);
fetch({error, _}, Req0, _MCID) ->
    json(503, #{error => mesh_unavailable}, Req0, #{}).

served({ok, Bin}, Req0) ->
    Req = cowboy_req:reply(200,
        #{<<"content-type">> => <<"application/octet-stream">>}, Bin, Req0),
    {ok, Req, #{}};
served({error, not_found}, Req0) ->
    json(404, #{error => not_found}, Req0, #{});
served({error, R}, Req0) ->
    json(502, #{error => get_failed, reason => fmt(R)}, Req0, #{}).


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
