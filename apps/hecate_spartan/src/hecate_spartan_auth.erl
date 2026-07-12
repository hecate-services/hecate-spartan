%%% @doc UCAN authentication for the entity-facing API.
%%%
%%% Entities present the UCAN we minted at registration as a bearer token.
%%% We verify it against our issuer key (signature, expiry) and treat the
%%% token's audience as the caller's DID. Capability checks gate send/recv.
-module(hecate_spartan_auth).

-export([authenticate/1, authenticate_token/1, has_cap/2]).

%% @doc Authenticate a cowboy request via its `Authorization: Bearer' header.
%% Returns the caller's DID and the decoded UCAN payload.
-spec authenticate(cowboy_req:req()) ->
    {ok, binary(), map()} | {error, atom()}.
authenticate(Req) ->
    case cowboy_req:header(<<"authorization">>, Req) of
        <<"Bearer ", Token/binary>> -> authenticate_token(Token);
        undefined                   -> {error, missing_authorization};
        _                           -> {error, malformed_authorization}
    end.

%% @doc Verify a UCAN token and return {ok, AudienceDid, Payload}.
-spec authenticate_token(binary()) -> {ok, binary(), map()} | {error, atom()}.
authenticate_token(Token) ->
    case hecate_spartan_identity:verify_ucan(Token) of
        {ok, Payload} ->
            case maps:get(<<"aud">>, Payload, undefined) of
                Aud when is_binary(Aud), Aud =/= <<>> -> {ok, Aud, Payload};
                _                                     -> {error, no_audience}
            end;
        {error, _} ->
            {error, invalid_ucan}
    end.

%% @doc True if the UCAN payload grants a capability with the given `can'
%% action (e.g. <<"msg/send">>, <<"msg/recv">>).
-spec has_cap(map(), binary()) -> boolean().
has_cap(Payload, Can) ->
    Caps = maps:get(<<"cap">>, Payload, []),
    lists:any(fun(C) -> maps:get(<<"can">>, C, undefined) =:= Can end, Caps).
