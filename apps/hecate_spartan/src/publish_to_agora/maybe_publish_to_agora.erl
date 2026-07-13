%%% @doc Handler for the publish_to_agora command.
%%%
%%% Pure domain logic: validate and emit. Authorisation (the entity's UCAN must
%%% carry `agora/post') is an ingress concern, enforced before dispatch.
-module(maybe_publish_to_agora).

-export([handle/1, handle_from_map/1, dispatch/1]).

-dialyzer({nowarn_function, [dispatch/1]}).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{post_id := P, from := F, body := B} = Payload) ->
    At = maps:get(posted_at, Payload, erlang:system_time(millisecond)),
    R = maps:get(in_reply_to, Payload, undefined),
    handle(publish_to_agora_v1:new(P, F, B, R, At));
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(publish_to_agora_v1:publish_to_agora_v1()) ->
    {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{from := F, body := B} = Map = publish_to_agora_v1:to_map(Command),
    case validate(F, B) of
        ok ->
            Event = agora_post_published_v1:new(Map),
            {ok, [agora_post_published_v1:to_map(Event)]};
        {error, Reason} ->
            {error, Reason}
    end.

-spec dispatch(publish_to_agora_v1:publish_to_agora_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{post_id := PostId} = CmdMap = publish_to_agora_v1:to_map(Cmd),
    EvoqCmd = evoq_command:new(
        publish_to_agora,
        agora_aggregate,
        agora_aggregate:stream_id(PostId),
        CmdMap,
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{store_id => hecate_spartan_store,
             adapter => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).

validate(From, Body) ->
    case {byte_size(From), byte_size(Body)} of
        {0, _} -> {error, from_required};
        {_, 0} -> {error, empty_body};
        _      -> ok
    end.
