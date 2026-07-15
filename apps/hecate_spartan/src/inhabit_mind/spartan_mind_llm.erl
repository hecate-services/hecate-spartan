%%% @doc The one place a mind reaches off the BEAM: a single HTTP call to Melious
%%% (sovereign-EU inference, OpenAI-compatible) that turns a threat into a
%%% judgment. No streaming, no client library, no state. Just the request the
%%% cognition needs, and the two lines of the answer it keeps.
%%%
%%% The key comes from the MELIOUS_API_KEY environment, never from config on
%%% disk. If it is absent the mind simply cannot reason, and says so, rather than
%%% crashing.
-module(spartan_mind_llm).

-export([reason/2]).

-define(URL, "https://api.melious.ai/v1/chat/completions").
-define(MODEL, <<"qwen3.5-9b">>).
-define(TIMEOUT_MS, 120000).

-spec reason(binary(), binary()) -> {ok, binary()} | {error, term()}.
reason(Character, Stimulus) ->
    case os:getenv("MELIOUS_API_KEY") of
        false -> {error, no_api_key};
        ""    -> {error, no_api_key};
        Key   -> call(Key, Character, Stimulus)
    end.

call(Key, Character, Stimulus) ->
    Body = jsx:encode(#{
        <<"model">>       => ?MODEL,
        <<"temperature">> => 0.4,
        <<"max_tokens">>  => 400,
        <<"messages">>    => [
            #{<<"role">> => <<"system">>, <<"content">> => Character},
            #{<<"role">> => <<"user">>,   <<"content">> => Stimulus}
        ]
    }),
    Headers = [{"authorization", "Bearer " ++ Key}],
    Request = {?URL, Headers, "application/json", Body},
    HttpOpts = [{timeout, ?TIMEOUT_MS}, {ssl, tls_opts()}],
    case httpc:request(post, Request, HttpOpts, [{body_format, binary}]) of
        {ok, {{_, 200, _}, _RH, Resp}}  -> parse(Resp);
        {ok, {{_, Code, _}, _RH, Resp}} -> {error, {http, Code, snippet(Resp)}};
        {error, Reason}                 -> {error, Reason}
    end.

%% Verify the peer against the system trust store, and fall back to no
%% verification only if this OTP cannot produce cacerts (it can, on 25+).
tls_opts() ->
    try
        [{verify, verify_peer},
         {cacerts, public_key:cacerts_get()},
         {depth, 3},
         {customize_hostname_check,
          [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}]
    catch _:_ ->
        [{verify, verify_none}]
    end.

parse(Resp) ->
    try
        Json = jsx:decode(Resp, [return_maps]),
        [Choice | _] = maps:get(<<"choices">>, Json),
        Content = maps:get(<<"content">>, maps:get(<<"message">>, Choice)),
        {ok, string:trim(Content)}
    catch _:_ ->
        {error, bad_response}
    end.

snippet(Bin) when is_binary(Bin) -> binary:part(Bin, 0, min(200, byte_size(Bin)));
snippet(Other)                   -> Other.
