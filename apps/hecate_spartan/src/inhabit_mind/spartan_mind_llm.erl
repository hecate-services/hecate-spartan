%%% @doc The one place a mind reaches off the BEAM to think. Two backends, one
%%% per mind, chosen by HECATE_MIND_BACKEND (the decoupled-identity path: a
%%% mind's engine is data, not baked in):
%%%
%%%   - melious : sovereign-EU broker, OpenAI-compatible. One key
%%%     (MELIOUS_API_KEY). Flaky under concurrent load, so retries with
%%%     exponential backoff + jitter.
%%%   - gemini  : Google generateContent. A POOL of keys (GEMINI_API_KEYS,
%%%     comma-separated); rotates through them per call and on failure, so per
%%%     key rate limits and exhaustion self-heal. Rotation is the retry.
%%%
%%% Splitting a society across both halves the concurrent load on each AND gives
%%% real cognitive diversity (different engines, different voices), the deepest
%%% antidote to sycophantic convergence.
-module(spartan_mind_llm).

-export([reason/2, reason_messages/1, reason_messages/2]).
-export([reason_tools/2, reason_tools/3, interpret_message/1, gemini_interpret/1]).

-define(MELIOUS_URL, "https://api.melious.ai/v1/chat/completions").
-define(MELIOUS_MODEL, <<"qwen3.5-9b">>).
-define(GEMINI_MODEL, "gemini-3-flash-preview").
-define(GEMINI_URL,
        "https://generativelanguage.googleapis.com/v1beta/models/"
        ?GEMINI_MODEL ":generateContent").
-define(TIMEOUT_MS, 120000).

%% Melious retries transient failures (400 "malformed", unparseable 200s) with
%% exponential backoff + jitter so a society does not retry in lockstep.
-define(ATTEMPTS, 6).
-define(BASE_BACKOFF_MS, 400).
-define(JITTER_MS, 500).

%% Temperature is temperament: higher = more varied and willing to diverge (an
%% antidote to mode-collapse); lower = measured. Per node via
%% HECATE_MIND_TEMPERATURE, else app-env, else this default.
-define(DEFAULT_TEMP, 0.7).

%% ===================================================================
%% Public API
%% ===================================================================

-spec reason(binary(), binary()) -> {ok, binary()} | {error, term()}.
reason(Character, Stimulus) ->
    reason_messages([
        #{<<"role">> => <<"system">>, <<"content">> => Character},
        #{<<"role">> => <<"user">>,   <<"content">> => Stimulus}
    ]).

-spec reason_messages([map()]) -> {ok, binary()} | {error, term()}.
reason_messages(Messages) ->
    reason_messages(Messages, ?MELIOUS_MODEL).

-spec reason_messages([map()], binary()) -> {ok, binary()} | {error, term()}.
reason_messages(Messages, _Model) ->
    case reason_tools(Messages, []) of
        {ok, {Text, _Calls, _Tokens}} -> {ok, Text};
        {error, _} = E                -> E
    end.

%% @doc Reason with tools offered. Returns the mind's private text (its thought,
%% which may be empty), the tool calls it chose, and the token cost. Dispatches
%% to the mind's backend.
-spec reason_tools([map()], [map()]) ->
    {ok, {binary(), [map()], non_neg_integer()}} | {error, term()}.
reason_tools(Messages, Tools) ->
    case backend() of
        gemini  -> gemini_reason(Messages, Tools);
        melious -> melious_reason(Messages, Tools)
    end.

-spec reason_tools([map()], [map()], binary()) ->
    {ok, {binary(), [map()], non_neg_integer()}} | {error, term()}.
reason_tools(Messages, Tools, _Model) ->
    reason_tools(Messages, Tools).

backend() ->
    case os:getenv("HECATE_MIND_BACKEND") of
        "gemini" -> gemini;
        _Other   -> melious
    end.

%% ===================================================================
%% Melious backend (OpenAI-compatible, one key, backoff+jitter retry)
%% ===================================================================

melious_reason(Messages, Tools) ->
    case os:getenv("MELIOUS_API_KEY") of
        false -> {error, no_api_key};
        ""    -> {error, no_api_key};
        Key   -> melious_call(Key, Messages, Tools)
    end.

melious_call(Key, Messages, Tools) ->
    Body = jsx:encode(with_tools(#{
        <<"model">>       => ?MELIOUS_MODEL,
        <<"temperature">> => temperature(),
        <<"max_tokens">>  => 400,
        <<"messages">>    => Messages
    }, Tools)),
    melious_attempt(Body, Key, ?ATTEMPTS).

melious_attempt(Body, Key, N) ->
    Request = {?MELIOUS_URL, [{"authorization", "Bearer " ++ Key}],
               "application/json", Body},
    case httpc:request(post, Request, http_opts(), [{body_format, binary}]) of
        {ok, {{_, 200, _}, _RH, Resp}}  -> melious_on_ok(melious_parse(Resp), Body, Key, N);
        {ok, {{_, Code, _}, _RH, Resp}} -> melious_retry(Body, Key, N, {http, Code, snippet(Resp)});
        {error, Reason}                 -> melious_retry(Body, Key, N, Reason)
    end.

melious_on_ok({ok, _} = Ok, _Body, _Key, _N) ->
    Ok;
melious_on_ok({error, bad_response}, Body, Key, N) ->
    melious_retry(Body, Key, N, bad_response).

melious_retry(_Body, _Key, 1, Why) ->
    {error, Why};
melious_retry(Body, Key, N, Why) ->
    Delay = (?BASE_BACKOFF_MS bsl (?ATTEMPTS - N)) + rand:uniform(?JITTER_MS),
    logger:info("[spartan_mind_llm] melious transient (~p); retry in ~bms (~b left)",
                [Why, Delay, N - 1]),
    timer:sleep(Delay),
    melious_attempt(Body, Key, N - 1).

with_tools(Base, [])    -> Base;
with_tools(Base, Tools) -> Base#{<<"tools">> => Tools, <<"tool_choice">> => <<"auto">>}.

melious_parse(Resp) ->
    try
        Json = jsx:decode(Resp, [return_maps]),
        [Choice | _] = maps:get(<<"choices">>, Json),
        {Text, Calls} = interpret_message(maps:get(<<"message">>, Choice)),
        {ok, {Text, Calls, melious_tokens(Json)}}
    catch _:_ ->
        {error, bad_response}
    end.

melious_tokens(Json) ->
    case maps:get(<<"usage">>, Json, undefined) of
        #{<<"total_tokens">> := T} when is_integer(T) -> T;
        _NoUsage                                      -> 0
    end.

%% @doc Split an OpenAI-style message into private text and tool calls. Exported
%% for testing the protocol without a live backend.
-spec interpret_message(map()) -> {binary(), [map()]}.
interpret_message(Msg) ->
    Calls = lists:filtermap(fun interpret_call/1,
                            maps:get(<<"tool_calls">>, Msg, [])),
    {thought_text(Msg), Calls}.

%% qwen3.5-9b is a reasoning model: content is null on a tool turn, the thought
%% is in reasoning_content. Prefer content, else reasoning; never lose it.
thought_text(Msg) ->
    case maps:get(<<"content">>, Msg, null) of
        C when is_binary(C), C =/= <<>> -> string:trim(C);
        _AbsentOrEmpty                  -> reasoning_text(Msg)
    end.

reasoning_text(Msg) ->
    case maps:get(<<"reasoning_content">>, Msg, null) of
        R when is_binary(R) -> string:trim(R);
        _NoReasoning        -> <<>>
    end.

interpret_call(#{<<"function">> := #{<<"name">> := Name, <<"arguments">> := Args}}) ->
    {true, #{name => Name, args => decode_args(Args)}};
interpret_call(_) ->
    false.

decode_args(Args) when is_binary(Args) ->
    try jsx:decode(Args, [return_maps]) catch _:_ -> #{} end;
decode_args(Args) when is_map(Args) ->
    Args;
decode_args(_) ->
    #{}.

%% ===================================================================
%% Gemini backend (generateContent, key-pool rotation)
%% ===================================================================

gemini_reason(Messages, Tools) ->
    case gemini_pool() of
        []   -> {error, no_api_key};
        Pool -> gemini_send(gemini_body(Messages, Tools), shuffle(Pool))
    end.

%% Try each key in a shuffled pool once; rotate on any failure. With ~10 keys a
%% fresh key sidesteps per key rate limits and exhaustion, so this both retries
%% and load-balances.
gemini_send(_Body, []) ->
    {error, gemini_all_keys_failed};
gemini_send(Body, [Key | Rest]) ->
    case gemini_once(Body, Key) of
        {ok, _} = Ok ->
            Ok;
        {error, Why} when Rest =:= [] ->
            {error, Why};
        {error, Why} ->
            logger:info("[spartan_mind_llm] gemini key failed (~p); rotating (~b left)",
                        [Why, length(Rest)]),
            timer:sleep(rand:uniform(?JITTER_MS)),
            gemini_send(Body, Rest)
    end.

gemini_once(Body, Key) ->
    Request = {?GEMINI_URL, [{"x-goog-api-key", Key}], "application/json", Body},
    case httpc:request(post, Request, http_opts(), [{body_format, binary}]) of
        {ok, {{_, 200, _}, _RH, Resp}}  -> gemini_parse(Resp);
        {ok, {{_, Code, _}, _RH, Resp}} -> {error, {http, Code, snippet(Resp)}};
        {error, Reason}                 -> {error, Reason}
    end.

gemini_pool() ->
    case os:getenv("GEMINI_API_KEYS") of
        false -> [];
        ""    -> [];
        S     -> [K || Part <- string:tokens(S, ","), (K = string:trim(Part)) =/= ""]
    end.

gemini_body(Messages, Tools) ->
    {Systems, Contents} = partition_messages(Messages),
    Base = #{<<"contents">> => Contents,
             <<"generationConfig">> => #{<<"temperature">> => temperature(),
                                         <<"maxOutputTokens">> => 400}},
    jsx:encode(add_gemini_tools(add_system(Base, Systems), Tools)).

partition_messages(Messages) ->
    Systems  = [content(M) || M <- Messages, mget(role, M) =:= <<"system">>],
    Contents = [gemini_content(M) || M <- Messages, mget(role, M) =/= <<"system">>],
    {Systems, Contents}.

gemini_content(M) ->
    #{<<"role">> => gemini_role(mget(role, M)),
      <<"parts">> => [#{<<"text">> => content(M)}]}.

gemini_role(<<"assistant">>) -> <<"model">>;
gemini_role(_UserOrOther)    -> <<"user">>.

add_system(Base, []) ->
    Base;
add_system(Base, Systems) ->
    Base#{<<"systemInstruction">> =>
              #{<<"parts">> => [#{<<"text">> => iolist_to_binary(lists:join(<<"\n\n">>, Systems))}]}}.

add_gemini_tools(Base, []) ->
    Base;
add_gemini_tools(Base, Tools) ->
    Base#{<<"tools">> => [#{<<"functionDeclarations">> => [fn_decl(T) || T <- Tools]}]}.

fn_decl(T) ->
    mget(function, T).

gemini_parse(Resp) ->
    try
        Json = jsx:decode(Resp, [return_maps]),
        [Cand | _] = maps:get(<<"candidates">>, Json),
        Parts = maps:get(<<"parts">>, maps:get(<<"content">>, Cand), []),
        {Text, Calls} = gemini_interpret(Parts),
        {ok, {Text, Calls, gemini_tokens(Json)}}
    catch _:_ ->
        {error, bad_response}
    end.

%% @doc Turn Gemini content parts into private text + tool calls. Exported for
%% testing. functionCall.args is already a decoded object (unlike OpenAI's JSON
%% string), so it maps straight to our internal shape.
-spec gemini_interpret([map()]) -> {binary(), [map()]}.
gemini_interpret(Parts) ->
    Texts = [T || #{<<"text">> := T} <- Parts, is_binary(T)],
    Calls = [#{name => N, args => A}
             || #{<<"functionCall">> := #{<<"name">> := N, <<"args">> := A}} <- Parts],
    {string:trim(iolist_to_binary(lists:join(<<" ">>, Texts))), Calls}.

gemini_tokens(Json) ->
    case maps:get(<<"usageMetadata">>, Json, undefined) of
        #{<<"totalTokenCount">> := T} when is_integer(T) -> T;
        _NoUsage                                         -> 0
    end.

%% ===================================================================
%% Shared
%% ===================================================================

http_opts() ->
    [{timeout, ?TIMEOUT_MS}, {ssl, tls_opts()}].

%% Verify the peer against the system trust store; fall back only if this OTP
%% cannot produce cacerts (it can, on 25+).
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

temperature() ->
    case os:getenv("HECATE_MIND_TEMPERATURE") of
        V when is_list(V), V =/= "" -> parse_temp(V);
        _Unset                      -> application:get_env(hecate_spartan, mind_temperature, ?DEFAULT_TEMP)
    end.

parse_temp(S) ->
    case string:to_float(S) of
        {F, _} when is_float(F) -> F;
        _NotFloat               -> parse_temp_int(S)
    end.

parse_temp_int(S) ->
    case string:to_integer(S) of
        {I, _} when is_integer(I) -> float(I);
        _NotInt                   -> ?DEFAULT_TEMP
    end.

%% Random permutation of the key pool, so rotation starts at a different key each
%% call and load spreads across the pool.
shuffle(List) ->
    [K || {_, K} <- lists:sort([{rand:uniform(), X} || X <- List])].

content(M) -> mget(content, M).

mget(Key, Map) ->
    maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, undefined)).

snippet(Bin) when is_binary(Bin) -> binary:part(Bin, 0, min(200, byte_size(Bin)));
snippet(Other)                   -> Other.
