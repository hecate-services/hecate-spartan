%%% @doc Where a mind reaches off the BEAM to think. A mind's engine is data
%%% (HECATE_MIND_BACKEND), not baked in: the same Soul can think with any of
%%% several providers. Splitting a society across backends halves the concurrent
%%% load on each AND gives real cognitive diversity (different engines, different
%%% families of voice), the deepest antidote to sycophantic convergence.
%%%
%%% Backends:
%%%   - melious : sovereign-EU broker, OpenAI-compatible. MELIOUS_API_KEY.
%%%   - groq    : fast, OpenAI-compatible, gpt-oss model. GROQ_API_KEYS.
%%%   - gemini  : Google generateContent (different shape). GEMINI_API_KEYS.
%%%
%%% Every backend takes a POOL of keys (comma-separated; a lone key is a pool of
%%% one) and rotates through them per call and on failure, with exponential
%%% backoff + jitter, so per key rate limits and provider bad-windows self-heal
%%% and a society does not retry in lockstep. Adding another OpenAI-compatible
%%% provider is a line in backend_config/0.
-module(spartan_mind_llm).

-export([reason/2, reason_messages/1, reason_messages/2]).
-export([reason_tools/2, reason_tools/3, interpret_message/1, gemini_interpret/1]).

-define(MELIOUS_URL, "https://api.melious.ai/v1/chat/completions").
-define(MELIOUS_MODEL, <<"qwen3.5-9b">>).
-define(GROQ_URL, "https://api.groq.com/openai/v1/chat/completions").
-define(GROQ_MODEL, <<"openai/gpt-oss-20b">>).
-define(CEREBRAS_URL, "https://api.cerebras.ai/v1/chat/completions").
-define(CEREBRAS_MODEL, <<"zai-glm-4.7">>).
-define(MISTRAL_URL, "https://api.mistral.ai/v1/chat/completions").
-define(MISTRAL_MODEL, <<"mistral-small-latest">>).
-define(GEMINI_MODEL, "gemini-3-flash-preview").
-define(GEMINI_URL,
        "https://generativelanguage.googleapis.com/v1beta/models/"
        ?GEMINI_MODEL ":generateContent").

-define(TIMEOUT_MS, 120000).
-define(MAX_TOKENS, 500).
-define(ATTEMPTS, 6).
-define(BASE_BACKOFF_MS, 400).
-define(JITTER_MS, 500).
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

%% @doc Reason with tools offered, on the mind's backend. Returns the mind's
%% private text (may be empty), the tool calls it chose, and the token cost.
-spec reason_tools([map()], [map()]) ->
    {ok, {binary(), [map()], non_neg_integer()}} | {error, term()}.
reason_tools(Messages, Tools) ->
    C = backend_config(),
    case keys(C) of
        []   -> {error, no_api_key};
        Keys -> send(C, body(C, Messages, Tools), keyseq(Keys, ?ATTEMPTS), 1)
    end.

-spec reason_tools([map()], [map()], binary()) ->
    {ok, {binary(), [map()], non_neg_integer()}} | {error, term()}.
reason_tools(Messages, Tools, _Model) ->
    reason_tools(Messages, Tools).

backend_config() ->
    case os:getenv("HECATE_MIND_BACKEND") of
        "gemini" -> #{fmt => gemini, url => ?GEMINI_URL, keyenv => "GEMINI_API_KEYS"};
        "groq"   -> #{fmt => openai, url => ?GROQ_URL, model => ?GROQ_MODEL,
                      keyenv => "GROQ_API_KEYS", label => "groq"};
        "cerebras" -> #{fmt => openai, url => ?CEREBRAS_URL, model => ?CEREBRAS_MODEL,
                      keyenv => "CEREBRAS_API_KEYS", label => "cerebras"};
        "mistral" -> #{fmt => openai, url => ?MISTRAL_URL, model => ?MISTRAL_MODEL,
                      keyenv => "MISTRAL_API_KEYS", label => "mistral"};
        _Melious -> #{fmt => openai, url => ?MELIOUS_URL, model => ?MELIOUS_MODEL,
                      keyenv => "MELIOUS_API_KEY", label => "melious"}
    end.

%% ===================================================================
%% The shared send loop: rotate the key pool, backoff+jitter on failure
%% ===================================================================

send(_C, _Body, [], _Attempt) ->
    {error, all_attempts_failed};
send(C, Body, [Key | Rest], Attempt) ->
    case once(C, Body, Key) of
        {ok, _} = Ok ->
            Ok;
        {error, Why} when Rest =:= [] ->
            {error, Why};
        {error, Why} ->
            Delay = (?BASE_BACKOFF_MS bsl min(Attempt - 1, 5)) + rand:uniform(?JITTER_MS),
            logger:info("[spartan_mind_llm] ~s transient (~p); retry in ~bms",
                        [maps:get(label, C, "gemini"), Why, Delay]),
            timer:sleep(Delay),
            send(C, Body, Rest, Attempt + 1)
    end.

once(#{fmt := openai, url := Url}, Body, Key) ->
    http_do({Url, [{"authorization", "Bearer " ++ Key}], "application/json", Body},
            fun openai_parse/1);
once(#{fmt := gemini, url := Url}, Body, Key) ->
    http_do({Url, [{"x-goog-api-key", Key}], "application/json", Body},
            fun gemini_parse/1).

http_do(Request, ParseFun) ->
    case httpc:request(post, Request, http_opts(), [{body_format, binary}]) of
        {ok, {{_, 200, _}, _RH, Resp}}  -> ParseFun(Resp);
        {ok, {{_, Code, _}, _RH, Resp}} -> {error, {http, Code, snippet(Resp)}};
        {error, Reason}                 -> {error, Reason}
    end.

%% A shuffled pool cycled to ?ATTEMPTS entries: many keys rotate to fresh ones,
%% a lone key is retried in place (its provider's failover may route elsewhere).
keyseq(Keys, N) ->
    Shuffled = shuffle(Keys),
    lists:sublist(lists:append(lists:duplicate((N div length(Shuffled)) + 1, Shuffled)), N).

keys(#{keyenv := Env}) ->
    case os:getenv(Env) of
        false -> [];
        ""    -> [];
        S     -> [K || Part <- string:tokens(S, ","), (K = string:trim(Part)) =/= ""]
    end.

body(#{fmt := openai, model := Model}, Messages, Tools) ->
    jsx:encode(with_tools(#{<<"model">>       => Model,
                            <<"temperature">> => temperature(),
                            <<"max_tokens">>  => ?MAX_TOKENS,
                            <<"messages">>    => Messages}, Tools));
body(#{fmt := gemini}, Messages, Tools) ->
    gemini_body(Messages, Tools).

with_tools(Base, [])    -> Base;
with_tools(Base, Tools) -> Base#{<<"tools">> => Tools, <<"tool_choice">> => <<"auto">>}.

%% ===================================================================
%% OpenAI-compatible parsing (Melious, Groq)
%% ===================================================================

openai_parse(Resp) ->
    try
        Json = jsx:decode(Resp, [return_maps]),
        [Choice | _] = maps:get(<<"choices">>, Json),
        {Text, Calls} = interpret_message(maps:get(<<"message">>, Choice)),
        {ok, {Text, Calls, openai_tokens(Json)}}
    catch _:_ ->
        {error, bad_response}
    end.

openai_tokens(Json) ->
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

%% A reasoning model (qwen) puts content at null on a tool turn and the thought
%% in reasoning_content. Prefer content, else reasoning; never lose it.
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
%% Gemini backend (generateContent shape)
%% ===================================================================

gemini_body(Messages, Tools) ->
    {Systems, Contents} = partition_messages(Messages),
    Base = #{<<"contents">> => Contents,
             <<"generationConfig">> => #{<<"temperature">> => temperature(),
                                         <<"maxOutputTokens">> => ?MAX_TOKENS}},
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
    Base#{<<"tools">> => [#{<<"functionDeclarations">> => [mget(function, T) || T <- Tools]}]}.

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

%% @doc Gemini content parts -> private text + tool calls. functionCall.args is
%% already a decoded object. Exported for testing.
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
%% Shared helpers
%% ===================================================================

http_opts() ->
    [{timeout, ?TIMEOUT_MS}, {ssl, tls_opts()}].

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

shuffle(List) ->
    [K || {_, K} <- lists:sort([{rand:uniform(), X} || X <- List])].

content(M) -> mget(content, M).

mget(Key, Map) ->
    maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, undefined)).

snippet(Bin) when is_binary(Bin) -> binary:part(Bin, 0, min(200, byte_size(Bin)));
snippet(Other)                   -> Other.
