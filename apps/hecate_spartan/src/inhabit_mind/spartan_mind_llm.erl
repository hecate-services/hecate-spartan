%%% @doc Where a mind reaches off the BEAM to think. A mind's engines are data
%%% (HECATE_MIND_PROVIDERS), not baked in: the same Soul can think with any of
%%% several providers, and can carousel across a POOL of them turn to turn.
%%% Spreading a society across backends AND letting each mind rotate providers
%%% gives two wins at once: concurrent load is shared, and there is real
%%% cognitive diversity (different engines, different families of voice), the
%%% deepest antidote to sycophantic convergence.
%%%
%%% Providers (each a clause in provider_config/1):
%%%   - melious  : sovereign-EU broker, OpenAI-compatible. MELIOUS_API_KEY.
%%%   - mistral  : sovereign-EU, OpenAI-compatible. MISTRAL_API_KEYS.
%%%   - cerebras : fast, OpenAI-compatible, GLM model. CEREBRAS_API_KEYS.
%%%   - groq     : fast, OpenAI-compatible, gpt-oss model. GROQ_API_KEYS.
%%%   - gemini   : Google generateContent (different shape). GEMINI_API_KEYS.
%%%
%%% A mind's HECATE_MIND_PROVIDERS is an ordered CSV of provider names. Each
%%% provider takes a POOL of keys (comma-separated; a lone key is a pool of one).
%%% A call builds a PROVIDER-FIRST round-robin schedule across every configured
%%% provider that has keys, one key per slot, capped at ?ATTEMPTS, with
%%% exponential backoff + jitter between slots. Provider-first means a failure
%%% falls straight to a DIFFERENT provider on the next try: when one broker has a
%%% bad window, another answers, and per-key rate limits self-heal without the
%%% society retrying in lockstep. Adding a provider is a clause in
%%% provider_config/1 plus a name in a mind's HECATE_MIND_PROVIDERS.
-module(spartan_mind_llm).

-export([reason/2, reason_messages/1, reason_messages/2]).
-export([reason_tools/2, reason_tools/3, interpret_message/1, gemini_interpret/1]).
-export([provider_labels/0]).

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
    case attempts() of
        []       -> {error, no_backend};
        Schedule -> send(Messages, Tools, Schedule, 1)
    end.

-spec reason_tools([map()], [map()], binary()) ->
    {ok, {binary(), [map()], non_neg_integer()}} | {error, term()}.
reason_tools(Messages, Tools, _Model) ->
    reason_tools(Messages, Tools).

%% @doc The provider pool a mind thinks with, as a human CSV, for the HUD.
-spec provider_labels() -> binary().
provider_labels() ->
    iolist_to_binary(lists:join(<<",">>, [unicode:characters_to_binary(P) || P <- providers()])).

%% The ordered provider pool this mind carousels. HECATE_MIND_PROVIDERS is the
%% primary source (CSV); a bare HECATE_MIND_BACKEND is honoured as a pool of one
%% so a single-provider node still works; the last resort is melious.
providers() ->
    case os:getenv("HECATE_MIND_PROVIDERS") of
        S when is_list(S), S =/= "" -> split_csv(S);
        _Unset                      -> default_providers()
    end.

default_providers() ->
    case os:getenv("HECATE_MIND_BACKEND") of
        B when is_list(B), B =/= "" -> [B];
        _Unset                      -> ["melious"]
    end.

split_csv(S) ->
    [T || Part <- string:tokens(S, ","), (T = string:trim(Part)) =/= ""].

provider_config("gemini")   -> #{fmt => gemini, url => ?GEMINI_URL,
                                 keyenv => "GEMINI_API_KEYS", label => "gemini"};
provider_config("groq")     -> #{fmt => openai, url => ?GROQ_URL, model => ?GROQ_MODEL,
                                 keyenv => "GROQ_API_KEYS", label => "groq"};
provider_config("cerebras") -> #{fmt => openai, url => ?CEREBRAS_URL, model => ?CEREBRAS_MODEL,
                                 keyenv => "CEREBRAS_API_KEYS", label => "cerebras"};
provider_config("mistral")  -> #{fmt => openai, url => ?MISTRAL_URL, model => ?MISTRAL_MODEL,
                                 keyenv => "MISTRAL_API_KEYS", label => "mistral"};
provider_config("melious")  -> #{fmt => openai, url => ?MELIOUS_URL, model => ?MELIOUS_MODEL,
                                 keyenv => "MELIOUS_API_KEY", label => "melious"};
provider_config(_Unknown)   -> undefined.

%% ===================================================================
%% The attempt schedule: a provider-first round robin over every provider
%% that has keys, one key per slot, cycling keys within a provider.
%% ===================================================================

%% Shuffle the provider order per call so successive turns draw a DIFFERENT
%% provider first: the carousel spreads load across every backend and milks each
%% free tier, rather than pinning the primary and only failing over. Keys within
%% a provider are shuffled too, so nothing is hit in lockstep.
attempts() ->
    schedule(shuffle(lists:filtermap(fun pool/1, providers())), ?ATTEMPTS).

pool(Name) ->
    case provider_config(Name) of
        undefined -> false;
        Config    -> pool_keys(Config, keys(Config))
    end.

pool_keys(_Config, [])  -> false;
pool_keys(Config, Keys) -> {true, {Config, shuffle(Keys)}}.

schedule([], _N) ->
    [];
schedule(Pools, N) ->
    NP = length(Pools),
    [slot(I, Pools, NP) || I <- lists:seq(0, N - 1)].

slot(I, Pools, NP) ->
    {Config, Keys} = lists:nth((I rem NP) + 1, Pools),
    {Config, lists:nth((I div NP rem length(Keys)) + 1, Keys)}.

%% ===================================================================
%% The shared send loop: walk the schedule, backoff+jitter on failure
%% ===================================================================

send(_M, _T, [], _N) ->
    {error, all_backends_exhausted};
send(Messages, Tools, [{Config, Key} | Rest], N) ->
    case once(Config, body(Config, Messages, Tools), Key) of
        {ok, _} = Ok ->
            Ok;
        {error, Why} when Rest =:= [] ->
            {error, Why};
        {error, Why} ->
            Delay = (?BASE_BACKOFF_MS bsl min(N - 1, 5)) + rand:uniform(?JITTER_MS),
            logger:info("[spartan_mind_llm] ~s transient (~p); rotating in ~bms",
                        [maps:get(label, Config, "?"), Why, Delay]),
            timer:sleep(Delay),
            send(Messages, Tools, Rest, N + 1)
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
