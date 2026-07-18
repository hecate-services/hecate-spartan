%%% @doc Embeddings for the mind's long-term memory — mesh-first, sovereign.
%%%
%%% The right home for embeddings is the mesh: `hecate-embedder' advertises
%%% `io.hecate.embed', exactly as `hecate-llm' advertises `hecate-llm.chat', so a
%%% mind reaches embeddings by mesh RPC — no key, no outbound HTTPS, no baked-in
%%% host, discoverable and load-balanced. That is the primary path here.
%%%
%%%   macula:call(Pool, Realm, <<"io.hecate.embed">>,
%%%               #{text => T, kind => query|passage}, T) -> {ok, #{vector => V}}
%%%
%%% Fallback: a direct local Ollama over plain HTTP (HECATE_EMBED_URL), for when
%%% the mesh embed service is not advertised (or the mesh is down). Either way,
%%% callers that get `error' fall back to lexical recall — the mind loses
%%% semantic precision, never its memory. `kind' selects the asymmetric-retrieval
%%% convention (query vs stored passage) for retrieval quality.
-module(embedder).

-export([embed/2]).

-define(TIMEOUT_MS, 8000).
-define(PROCEDURE, <<"io.hecate.embed">>).
-define(DEFAULT_URL, "http://127.0.0.1:11434/api/embeddings").
-define(DEFAULT_MODEL, <<"nomic-embed-text">>).

-spec embed(binary(), query | passage | raw) -> {ok, [float()]} | error.
embed(Text, Kind) when is_binary(Text), Text =/= <<>> ->
    embed_if(enabled(), Text, Kind);
embed(_NotText, _Kind) ->
    error.

%% A hard off-switch (app env `embed_enabled', default true): tests set it false
%% so the memory faculty exercises its lexical path with no mesh and no network.
embed_if(false, _Text, _Kind) ->
    error;
embed_if(true, Text, Kind) ->
    prefer_mesh(mesh_embed(Text, Kind), Text, Kind).

enabled() ->
    application:get_env(hecate_spartan, embed_enabled, true).

prefer_mesh({ok, _V} = Ok, _Text, _Kind) -> Ok;
prefer_mesh(_MissOrDark, Text, Kind)     -> over_http(Text, Kind).

%% --- mesh path: io.hecate.embed ---

%% Guarded: the client/realm lookups exit with noproc when hecate_om is not
%% running (e.g. under eunit), which must degrade to the fallback, not crash.
mesh_embed(Text, Kind) ->
    try call(hecate_om:macula_client(), hecate_om_identity:realm(), Text, Kind)
    catch _:_ -> error
    end.

call({ok, Pool}, {ok, Realm}, Text, Kind) ->
    reply_mesh(catch macula:call(Pool, Realm, ?PROCEDURE,
                                 #{text => Text, kind => Kind}, ?TIMEOUT_MS));
call(_Client, _Realm, _Text, _Kind) ->
    error.

reply_mesh({ok, Resp}) when is_map(Resp) -> vector_of(gf(vector, Resp));
reply_mesh(_Fail)                         -> error.

vector_of(V) when is_list(V), V =/= [] -> {ok, [num(X) || X <- V]};
vector_of(_NoVector)                   -> error.

gf(Key, Map) ->
    maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, undefined)).

%% --- fallback path: local Ollama over HTTP ---

over_http(Text, Kind) ->
    _ = application:ensure_all_started(inets),
    Body = jsx:encode(#{<<"model">> => model(), <<"prompt">> => prefixed(Kind, Text)}),
    reply_http(catch httpc:request(post, {url(), [], "application/json", Body},
                                   [{timeout, ?TIMEOUT_MS}], [{body_format, binary}])).

reply_http({ok, {{_V, 200, _R}, _H, Resp}}) ->
    parse_http(catch jsx:decode(Resp, [return_maps]));
reply_http(_FailOrNon200) ->
    error.

parse_http(#{<<"embedding">> := V}) when is_list(V), V =/= [] ->
    {ok, [num(X) || X <- V]};
parse_http(_NoEmbedding) ->
    error.

%% The asymmetric-retrieval convention the mesh service applies for us; on the
%% raw Ollama path we apply it ourselves so query and passage embeddings match.
prefixed(query, Text)   -> <<"search_query: ", Text/binary>>;
prefixed(passage, Text) -> <<"search_document: ", Text/binary>>;
prefixed(_Raw, Text)    -> Text.

num(X) when is_float(X)   -> X;
num(X) when is_integer(X) -> float(X);
num(_Other)               -> 0.0.

url() ->
    case os:getenv("HECATE_EMBED_URL") of
        U when is_list(U), U =/= "" -> U;
        _Unset                      -> ?DEFAULT_URL
    end.

model() ->
    case os:getenv("HECATE_EMBED_MODEL") of
        M when is_list(M), M =/= "" -> unicode:characters_to_binary(M);
        _Unset                      -> ?DEFAULT_MODEL
    end.
