%%% @doc How a mind turns text into a vector, over whichever transport is
%%% configured. Two modes:
%%%
%%%   mesh — call the `io.hecate.embed' capability advertised in the realm by
%%%          hecate-embedder. Location-transparent and realm-authenticated; the
%%%          relay finds the provider wherever it lives (crosses subnets where a
%%%          flat LAN URL cannot). This is where the macula:call lives — in
%%%          spartan, which already has a macula client — so the hecate_embed
%%%          library stays a clean, mesh-free dependency.
%%%
%%%   http — the earlier path: hecate_embed's `remote' backend HTTP-POSTs to a
%%%          hecate-embed service. Kept as the fallback until the mesh path is
%%%          proven on the fleet.
%%%
%%% Mode from HECATE_EMBED_MODE (mesh|http) or the `embed_mode' app-env; http by
%%% default so behaviour is unchanged until a deployment flips it. Every path is
%%% best-effort: a failure returns {error, _} and the caller (mind_memory)
%%% degrades to no recall rather than crashing a turn.
-module(spartan_embed).

-export([query/1, passage/1]).

-define(PROCEDURE, <<"io.hecate.embed">>).
-define(TIMEOUT_MS, 30000).

-spec query(binary()) -> {ok, [float()]} | {error, term()}.
query(Text) when is_binary(Text) -> embed(<<"query">>, Text).

-spec passage(binary()) -> {ok, [float()]} | {error, term()}.
passage(Text) when is_binary(Text) -> embed(<<"passage">>, Text).

embed(Kind, Text) ->
    dispatch(mode(), Kind, Text).

dispatch(mesh, Kind, Text) -> mesh_embed(Kind, Text);
dispatch(_Http, Kind, Text) -> http_embed(Kind, Text).

mode() ->
    case os:getenv("HECATE_EMBED_MODE") of
        "mesh" -> mesh;
        "http" -> http;
        _Unset -> application:get_env(hecate_spartan, embed_mode, http)
    end.

%% --- mesh: call the io.hecate.embed capability ---

mesh_embed(Kind, Text) ->
    call_mesh(catch hecate_om:macula_client(), catch hecate_om_identity:realm(), Kind, Text).

call_mesh({ok, Pool}, {ok, Realm}, Kind, Text) ->
    interpret(catch macula:call(Pool, Realm, ?PROCEDURE,
                                #{text => Text, kind => Kind}, ?TIMEOUT_MS));
call_mesh(_Client, _Realm, _Kind, _Text) ->
    {error, no_mesh}.

interpret({ok, Result}) when is_map(Result) ->
    to_vec(gv(vector, Result));
interpret(_Other) ->
    {error, mesh_call_failed}.

to_vec(V) when is_list(V) -> {ok, V};
to_vec(_NotAList)         -> {error, no_vector}.

%% --- http: hecate_embed's remote backend ---

http_embed(<<"query">>, Text)   -> with_model(fun(M) -> hecate_embed:embed_query(M, Text) end);
http_embed(<<"passage">>, Text) -> with_model(fun(M) -> hecate_embed:embed_passage(M, Text) end).

with_model(Fun) ->
    case hecate_embed:default_model() of
        {ok, Model}    -> Fun(Model);
        {error, _} = E -> E
    end.

%% CBOR may round-trip a map key as atom or binary; try atom then binary.
gv(Key, Map) ->
    maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, undefined)).
