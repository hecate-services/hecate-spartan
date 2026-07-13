%%% @doc Ingress: GET /v1/peers — the registry, for discovery + name->DID
%%% resolution. Any valid UCAN may read it.
-module(discover_api).

-export([init/2]).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> handle_get(Req0, State);
        _         -> json(405, #{error => method_not_allowed}, Req0, State)
    end.

handle_get(Req0, State) ->
    case hecate_spartan_auth:authenticate(Req0) of
        {ok, _Did, _Payload} ->
            %% Mesh-wide directory (local + federated peers), so a name resolves
            %% across the whole federation, not just this instance.
            Peers = [#{did => maps:get(did, E),
                       entity_name => maps:get(entity_name, E, null),
                       home => maps:get(home, E, null),
                       locale => null_if_undefined(maps:get(locale, E, undefined))}
                     || E <- hecate_spartan_mesh_entities:all()],
            json(200, #{peers => Peers}, Req0, State);
        {error, Reason} ->
            json(401, #{error => Reason}, Req0, State)
    end.

null_if_undefined(undefined) -> null;
null_if_undefined(V)         -> V.

json(Code, Map, Req0, State) ->
    Req = cowboy_req:reply(Code,
                           #{<<"content-type">> => <<"application/json">>},
                           jsx:encode(Map), Req0),
    {ok, Req, State}.
