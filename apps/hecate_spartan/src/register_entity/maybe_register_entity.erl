%%% @doc Handler for the register_entity command.
%%%
%%% Pure domain logic: validate the fields and emit entity_registered_v1.
%%% Proof-of-possession (the entity's signature over the registration
%%% challenge) is an authentication concern enforced at the ingress edge
%%% before dispatch — not here, and never stored in the event.
-module(maybe_register_entity).

-export([handle/1, handle_from_map/1, dispatch/1]).

-dialyzer({nowarn_function, [dispatch/1]}).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{entity_name := Name, did := Did, pubkey := PubKey} = Payload) ->
    At = maps:get(registered_at, Payload, erlang:system_time(millisecond)),
    handle(register_entity_v1:new(Name, Did, PubKey, At));
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(register_entity_v1:register_entity_v1()) ->
    {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{entity_name := Name, did := Did, pubkey := PubKey,
      registered_at := At} = register_entity_v1:to_map(Command),
    case validate(Name, Did, PubKey) of
        ok ->
            Event = entity_registered_v1:new(Name, Did, PubKey, At),
            {ok, [entity_registered_v1:to_map(Event)]};
        {error, Reason} ->
            {error, Reason}
    end.

-spec dispatch(register_entity_v1:register_entity_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{did := Did} = CmdMap = register_entity_v1:to_map(Cmd),
    EvoqCmd = evoq_command:new(
        register_entity,
        entity_aggregate,
        entity_aggregate:stream_id(Did),
        CmdMap,
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{store_id => hecate_spartan_store,
             adapter => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).

%% Internal — Ed25519 public keys are 32 raw bytes.
validate(Name, Did, PubKey) ->
    case {byte_size(Name), byte_size(Did), byte_size(PubKey)} of
        {0, _, _}  -> {error, entity_name_required};
        {_, 0, _}  -> {error, did_required};
        {_, _, 32} -> ok;
        {_, _, _}  -> {error, invalid_pubkey}
    end.
