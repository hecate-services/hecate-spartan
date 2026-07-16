%%% @doc The one place a mind reaches off the BEAM: a single HTTP call to Melious
%%% (sovereign-EU inference, OpenAI-compatible) that turns a threat into a
%%% judgment. No streaming, no client library, no state. Just the request the
%%% cognition needs, and the two lines of the answer it keeps.
%%%
%%% The key comes from the MELIOUS_API_KEY environment, never from config on
%%% disk. If it is absent the mind simply cannot reason, and says so, rather than
%%% crashing.
-module(spartan_mind_llm).

-export([reason/2, reason_messages/1, reason_messages/2]).
-export([reason_tools/2, reason_tools/3, interpret_message/1]).

-define(URL, "https://api.melious.ai/v1/chat/completions").
-define(MODEL, <<"qwen3.5-9b">>).
-define(TIMEOUT_MS, 120000).

%% Melious is an 11-provider failover broker: the SAME valid request is
%% sometimes 400-rejected by whichever backend it lands on, then accepted on a
%% retry that routes elsewhere. Observed ~2-in-3 rejection on the tools schema,
%% so a mind must retry transient failures rather than fall silent.
-define(ATTEMPTS, 4).
-define(RETRY_MS, 500).

%% Temperature is temperament: higher = more varied, surprising, willing to
%% diverge (an antidote to sycophantic mode-collapse); lower = measured and
%% terse. Per node via HECATE_MIND_TEMPERATURE, else app-env, else this default.
-define(DEFAULT_TEMP, 0.7).

%% @doc The flat two-message form: a persona and a single stimulus. Kept for
%% callers that have no assembled context; delegates to the message-list form.
-spec reason(binary(), binary()) -> {ok, binary()} | {error, term()}.
reason(Character, Stimulus) ->
    reason_messages([
        #{<<"role">> => <<"system">>, <<"content">> => Character},
        #{<<"role">> => <<"user">>,   <<"content">> => Stimulus}
    ]).

%% @doc Reason over a full assembled message list (the 4-layer context), on the
%% default model.
-spec reason_messages([map()]) -> {ok, binary()} | {error, term()}.
reason_messages(Messages) ->
    reason_messages(Messages, ?MODEL).

%% @doc Reason over a message list on a named model (the decoupled-identity
%% path: a mind may choose which backend it thinks with).
-spec reason_messages([map()], binary()) -> {ok, binary()} | {error, term()}.
reason_messages(Messages, Model) ->
    case do_request(Messages, [], Model) of
        {ok, {Text, _Calls, _Tokens}} -> {ok, Text};
        {error, _} = E                -> E
    end.

%% @doc Reason with tools offered. Returns the mind's private text (its thought
%% for this turn, which may be empty), the tool calls it chose to make, and the
%% total tokens the call cost. Text is never an action; only tool calls are.
-spec reason_tools([map()], [map()]) ->
    {ok, {binary(), [map()], non_neg_integer()}} | {error, term()}.
reason_tools(Messages, Tools) ->
    reason_tools(Messages, Tools, ?MODEL).

-spec reason_tools([map()], [map()], binary()) ->
    {ok, {binary(), [map()], non_neg_integer()}} | {error, term()}.
reason_tools(Messages, Tools, Model) ->
    do_request(Messages, Tools, Model).

do_request(Messages, Tools, Model) ->
    case os:getenv("MELIOUS_API_KEY") of
        false -> {error, no_api_key};
        ""    -> {error, no_api_key};
        Key   -> call(Key, Model, Messages, Tools)
    end.

call(Key, Model, Messages, Tools) ->
    Body = jsx:encode(with_tools(#{
        <<"model">>       => Model,
        <<"temperature">> => temperature(),
        <<"max_tokens">>  => 400,
        <<"messages">>    => Messages
    }, Tools)),
    attempt(Body, Key, ?ATTEMPTS).

%% The mind's temperament. Read once per call so a running mind can be retuned
%% by restarting with a new value; no nested try (elvis), parse defensively.
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

attempt(Body, Key, N) ->
    Request = {?URL, [{"authorization", "Bearer " ++ Key}],
               "application/json", Body},
    HttpOpts = [{timeout, ?TIMEOUT_MS}, {ssl, tls_opts()}],
    case httpc:request(post, Request, HttpOpts, [{body_format, binary}]) of
        {ok, {{_, 200, _}, _RH, Resp}}  -> parse(Resp);
        {ok, {{_, Code, _}, _RH, Resp}} -> retry(Body, Key, N, {http, Code, snippet(Resp)});
        {error, Reason}                 -> retry(Body, Key, N, Reason)
    end.

retry(_Body, _Key, 1, Why) ->
    {error, Why};
retry(Body, Key, N, Why) ->
    logger:info("[spartan_mind_llm] transient failure (~p); ~b attempts left",
                [Why, N - 1]),
    timer:sleep(?RETRY_MS),
    attempt(Body, Key, N - 1).

with_tools(Base, [])    -> Base;
with_tools(Base, Tools) -> Base#{<<"tools">> => Tools, <<"tool_choice">> => <<"auto">>}.

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
        {Text, Calls} = interpret_message(maps:get(<<"message">>, Choice)),
        {ok, {Text, Calls, total_tokens(Json)}}
    catch _:_ ->
        {error, bad_response}
    end.

total_tokens(Json) ->
    case maps:get(<<"usage">>, Json, undefined) of
        #{<<"total_tokens">> := T} when is_integer(T) -> T;
        _NoUsage                                      -> 0
    end.

%% @doc Split an OpenAI-style message into the mind's private text and the tool
%% calls it made. Exported for testing the protocol without a live backend.
-spec interpret_message(map()) -> {binary(), [map()]}.
interpret_message(Msg) ->
    Calls = lists:filtermap(fun interpret_call/1,
                            maps:get(<<"tool_calls">>, Msg, [])),
    {thought_text(Msg), Calls}.

%% A reasoning model (qwen3.5-9b) puts its `content' at null when it goes to a
%% tool call and carries the actual reasoning in `reasoning_content'. Prefer the
%% content when present, else the reasoning: either way, the mind's real thought
%% for the turn, never lost.
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

snippet(Bin) when is_binary(Bin) -> binary:part(Bin, 0, min(200, byte_size(Bin)));
snippet(Other)                   -> Other.
