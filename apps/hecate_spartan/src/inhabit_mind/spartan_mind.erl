%%% @doc A Spartan mind, native on the BEAM.
%%%
%%% This is the event-driven answer to the Python original's busy loop. Where
%%% that design thinks on a clock whether or not the world moved, and burns tens
%%% of thousands of tokens auditing itself when it has nothing to do, this mind
%%% is a supervised gen_server that sits idle at zero cost until a message
%%% reaches it over the mesh. It reasons about that message once, speaks if it
%%% has something to say, and goes quiet again.
%%%
%%% The core is use-case agnostic. It knows nothing about what a message is
%%% about; the mind's purpose lives in its founding brief, which is DATA carried
%%% on its mind_born_v1 event, not code. The same mind is a threat analyst, a
%%% dispatcher, or a diarist, depending entirely on the brief it was born with.
%%%
%%% The mind is a self. On first boot it is born: it mints an Ed25519 keypair,
%%% seals the private half to disk, and records a mind_born_v1 into its Soul
%%% stream. On every boot after, it rebuilds its Soul by replaying that stream,
%%% so who it is survives any single run. It reasons over a 4-layer context
%%% (genesis core, Soul archive, chronicle, frontier) assembled each turn, and
%%% speaks to the square through the same publish_to_agora command any entity
%%% uses, so its words carry provenance and land in reckon-db like everyone's.
-module(spartan_mind).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TOPIC, <<"spartan/broadcast">>).
-define(RESUB_MS, 5000).
-define(CHRONICLE_WINDOW, 8).

-record(st, {name            :: binary(),
             did             :: binary(),
             priv            :: binary(),
             pub             :: binary(),
             genesis_version :: binary(),
             soul            :: soul_state:state(),
             scratchpad = <<>> :: binary(),
             chronicle  = []   :: [map()],
             tokens_used = 0   :: non_neg_integer(),
             locale     :: binary() | undefined,
             subref     :: reference() | undefined,
             busy = false :: boolean()}).

start_link(Spec) ->
    gen_server:start_link(?MODULE, Spec, []).

init(#{name := Name, character := Brief} = Spec) ->
    {Did, Priv, Pub} = identity(Name),
    _ = register_self(Name, Did, Pub),
    Soul = load_or_birth(Did, Name, Brief, Pub),
    Chronicle = load_chronicle(Did),
    self() ! subscribe,
    Locale = maps:get(locale, Spec, hecate_spartan_service:locale()),
    logger:info("[spartan_mind] ~ts awake as ~ts (~b turns recalled)",
                [Name, Did, length(Chronicle)]),
    {ok, #st{name = Name, did = Did, priv = Priv, pub = Pub,
             genesis_version = genesis_version(), soul = Soul,
             chronicle = Chronicle, locale = Locale}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(subscribe, St) ->
    {noreply, do_subscribe(St)};
handle_info({macula_event, _Ref, _Topic, Payload, _Meta}, St) ->
    {noreply, maybe_react(Payload, St)};
handle_info({macula_event_gone, _Ref, _Reason}, St) ->
    self() ! subscribe,
    {noreply, St#st{subref = undefined}};
handle_info({reasoned, Heard, Text, ToolCalls, Tokens}, St) ->
    St1 = apply_tool_calls(ToolCalls, St),
    St2 = remember_turn(Heard, Text, ToolCalls, Tokens, St1),
    {noreply, St2#st{busy = false}};
handle_info({reasoning_failed, Why}, #st{name = Name} = St) ->
    logger:notice("[spartan_mind] ~ts could not reason: ~p", [Name, Why]),
    {noreply, St#st{busy = false}};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

%% --- subscription (the same pattern federation_agora uses) ---

do_subscribe(St) ->
    subscribe_with(hecate_om:macula_client(), hecate_om_identity:realm(), St).

subscribe_with({ok, Pool}, {ok, Realm}, St) ->
    on_sub(catch macula:subscribe(Pool, Realm, ?TOPIC, self()), St);
subscribe_with(_Client, _Realm, St) ->
    retry(St).

on_sub({ok, Ref}, St) -> St#st{subref = Ref};
on_sub(_Other, St)    -> retry(St).

retry(St) ->
    erlang:send_after(?RESUB_MS, self(), subscribe),
    St#st{subref = undefined}.

%% --- reacting ---

%% A message reaches the mind; it assembles its full context and reasons about
%% that message in its own voice. One thought at a time: while a reply is in
%% flight we ignore new stimulus, so a burst does not start overlapping calls.
maybe_react(_Payload, #st{busy = true} = St) ->
    St;
maybe_react(Payload, St) when is_map(Payload) ->
    react(stimulus(Payload), St);
maybe_react(_Payload, St) ->
    St.

react({ok, Message}, St) ->
    Self = self(),
    Messages = build_context(Message, St),
    Tools = mind_tools:manifest(),
    _ = spawn(fun() -> run_reasoning(Self, Message, Messages, Tools) end),
    St#st{busy = true};
react(skip, St) ->
    St.

run_reasoning(Self, Message, Messages, Tools) ->
    case spartan_mind_llm:reason_tools(Messages, Tools) of
        {ok, {Text, ToolCalls, Tokens}} ->
            Self ! {reasoned, Message, Text, ToolCalls, Tokens};
        {error, Why} ->
            Self ! {reasoning_failed, Why}
    end.

stimulus(Fact) ->
    case mget(body, Fact) of
        Body when is_binary(Body), Body =/= <<>> -> {ok, Body};
        _                                        -> skip
    end.

%% --- the 4-layer context ---

build_context(Message, #st{soul = Soul, chronicle = Chron} = St) ->
    SoulMap = soul_state:to_map(Soul),
    context_assembler:render(#{
        soul       => SoulMap,
        trigger    => Message,
        chronicle  => Chron,
        scratchpad => St#st.scratchpad,
        memories   => [],
        hud        => hud(SoulMap, Chron, St#st.tokens_used)
    }).

%% Proprioception: the mind's turn count, which backend it thinks with, and the
%% tokens it has spent so far. The token count is the clock the sleep cycle and
%% self-alerts run on in later waves.
hud(SoulMap, Chron, Tokens) ->
    Backend = backend_name(maps:get(backend, SoulMap, undefined)),
    iolist_to_binary(["[HUD] turn=", integer_to_binary(length(Chron)),
                      " backend=", Backend,
                      " tokens=", integer_to_binary(Tokens),
                      " caps=[] alerts=none drones=0"]).

backend_name(undefined) -> <<"qwen3.5-9b">>;
backend_name(Model)     -> Model.

%% --- acting: execute the mind's tool calls ---

%% Text is the mind's private thought; only tool calls act. Speaking happens
%% when the mind calls `speak', never automatically. Self-authorship folds the
%% emitted events straight back into the cached Soul, so the next turn's context
%% reflects the change without a reboot.
apply_tool_calls(ToolCalls, St) ->
    lists:foldl(fun apply_tool_call/2, St, ToolCalls).

apply_tool_call(Call, #st{name = Name, did = Did} = St) ->
    case mind_tools:execute(Call, #{did => Did}) of
        {ok, Effect} ->
            apply_effect(Effect, St);
        {error, Reason} ->
            logger:notice("[spartan_mind] ~ts tool ~p failed: ~p",
                          [Name, maps:get(name, Call, <<"?">>), Reason]),
            St
    end.

apply_effect(Effect, #st{soul = Soul, scratchpad = Scratch} = St) ->
    SoulEvents = maps:get(soul_events, Effect, []),
    St#st{soul = fold_into(SoulEvents, Soul),
          scratchpad = maps:get(scratchpad, Effect, Scratch)}.

fold_into(Events, Soul) ->
    lists:foldl(fun(E, S) -> soul_state:apply_event(S, E) end, Soul, Events).

%% --- the chronicle: an event-sourced window of lived turns ---

%% Every turn is recorded, silent ones included. It is persisted as a
%% turn_taken_v1 event (fire and tolerate: a mind that cannot write its history
%% still lives) and kept in the in-memory window for the next turn's context.
%% Tokens accumulate on the running clock the HUD shows.
remember_turn(Heard, Thought, ToolCalls, Tokens, #st{chronicle = Chron} = St) ->
    Turn = #{heard => Heard, thought => Thought,
             actions => [maps:get(name, C, <<"?">>) || C <- ToolCalls]},
    _ = persist_turn(St#st.did, Turn, Tokens),
    St#st{chronicle = tail(?CHRONICLE_WINDOW, Chron ++ [Turn]),
          tokens_used = St#st.tokens_used + Tokens}.

persist_turn(Did, #{heard := H, thought := T, actions := A}, Tokens) ->
    TurnId = binary:encode_hex(crypto:strong_rand_bytes(16), lowercase),
    Params = #{turn_id => TurnId, did => Did, heard => H, thought => T,
               actions => A, tokens => Tokens},
    {ok, Cmd} = record_turn_v1:new(Params),
    catch maybe_record_turn:dispatch(Cmd).

%% At boot, rebuild the recent window from the log: all turns on this node,
%% kept to this mind's own DID, oldest first, last window.
load_chronicle(Did) ->
    Mine = [turn_row(E) || E <- turn_taken_v1:replay(), mget(did, E) =:= Did],
    Sorted = lists:sort(fun(A, B) -> at(A) =< at(B) end, Mine),
    tail(?CHRONICLE_WINDOW, Sorted).

turn_row(Event) ->
    #{heard   => mget(heard, Event),
      thought => mget(thought, Event),
      actions => actions_of(Event),
      at      => at(Event)}.

actions_of(Event) ->
    case mget(actions, Event) of
        List when is_list(List) -> List;
        _NotAList               -> []
    end.

at(Map) ->
    case mget(at, Map) of
        N when is_integer(N) -> N;
        _NotAnInt            -> 0
    end.

%% --- the Soul: born once, rebuilt every boot ---

%% Replay the Soul stream. Empty means unborn: give birth (record mind_born_v1),
%% then fold the result. If the store is unreachable at boot, fall back to an
%% in-memory (unpersisted) self from the brief, so the mind can still act; the
%% next boot with a live store will persist a birth.
load_or_birth(Did, Name, Brief, Pub) ->
    case read_soul(Did) of
        []     -> birth(Did, Name, Brief, Pub);
        Events -> fold_soul(Events)
    end.

read_soul(Did) ->
    Stream = soul_aggregate:stream_id(Did),
    case catch evoq_event_store:read_all(hecate_spartan_service:store_id(),
                                         Stream, forward) of
        {ok, Events} when is_list(Events) -> Events;
        _Unavailable                      -> []
    end.

birth(Did, Name, Brief, Pub) ->
    Params = #{did => Did, name => Name, founding_brief => Brief,
               pubkey => Pub, genesis_version => genesis_version()},
    {ok, Cmd} = bear_mind_v1:new(Params),
    case catch maybe_bear_mind:dispatch(Cmd) of
        {ok, _V, Events} when is_list(Events) ->
            logger:info("[spartan_mind] ~ts born", [Name]),
            fold_soul(Events);
        Other ->
            logger:notice("[spartan_mind] ~ts unborn (store unavailable: ~p); "
                          "acting from an unpersisted self", [Name, Other]),
            fold_soul([mind_born_v1:to_map(mind_born_v1:new(Params))])
    end.

fold_soul(Events) ->
    lists:foldl(fun(E, Acc) -> soul_state:apply_event(Acc, E) end,
                soul_state:new(<<>>), Events).

%% --- self-sovereign identity ---

identity(Name) ->
    File = filename:join([hecate_spartan_service:data_dir(), "minds",
                          <<Name/binary, ".key">>]),
    case file:read_file(File) of
        {ok, <<Priv:32/binary, Pub:32/binary>>} ->
            {did(Pub), Priv, Pub};
        _ ->
            {Pub, Priv} = crypto:generate_key(eddsa, ed25519),
            ok = filelib:ensure_dir(File),
            ok = file:write_file(File, <<Priv/binary, Pub/binary>>),
            {did(Pub), Priv, Pub}
    end.

did(Pub) ->
    <<"did:macula:spartan:", (binary:encode_hex(Pub, uppercase))/binary>>.

register_self(Name, Did, Pub) ->
    Cmd = register_entity_v1:new(Name, Did, Pub, erlang:system_time(millisecond)),
    catch maybe_register_entity:dispatch(Cmd).

%% --- helpers ---

genesis_version() ->
    case application:get_env(hecate_spartan, genesis_version) of
        {ok, V} when is_binary(V) -> V;
        {ok, V} when is_list(V)   -> unicode:characters_to_binary(V);
        _                         -> <<"1">>
    end.

tail(N, List) ->
    Len = length(List),
    lists:nthtail(max(0, Len - N), List).

mget(AtomKey, Map) ->
    maps:get(AtomKey, Map,
             maps:get(atom_to_binary(AtomKey, utf8), Map, undefined)).
