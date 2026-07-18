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
%%% about; the mind's purpose lives in its founding brief, which is DATA written
%%% into its Soul at birth, not code. The same mind is a threat analyst, a
%%% dispatcher, or a diarist, depending entirely on the brief it was born with.
%%%
%%% The mind is a self. On first boot it is born: it mints an Ed25519 keypair,
%%% seals the private half to disk, and writes its identity and Soul archives to
%%% disk. Its Soul is a supervision tree of area-of-consciousness processes (see
%%% soul.erl), each owning its Markdown file, so who it is survives any single
%%% run and each faculty heals itself independently. It reasons over a 4-layer
%%% context (genesis core, Soul archive, chronicle, frontier) assembled each turn, and
%%% speaks to the square through the same publish_to_agora command any entity
%%% uses, so its words carry provenance and land in reckon-db like everyone's.
-module(spartan_mind).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-export([decide/5]).   %% the pre-LLM engagement gate, pure, exported for tests

%% A mind hears two things over the mesh: the broadcast channel (society-wide
%% stimulus, e.g. a sentinel digest) and the agora (every mind's public speech).
%% Hearing the agora is what lets a society converse rather than sit in parallel
%% silence.
%% A mission is not stimulus to react to; it is standing context. Published as a
%% fact on this topic (#{domain, directive}); a mind updates its mission set live
%% (empty directive clears that domain). This is how the society's work is
%% injected at runtime, from an operator or a use-case service.
-define(RESUB_MS, 5000).
-define(STM_SHOW, 5).

%% A mind reasons at most once per cooldown, so a lively square cannot spiral
%% into a token-burn loop. Env-driven per node (HECATE_MIND_COOLDOWN_MS), else
%% app-env `mind_cooldown_ms'. Default raised to 60s: at paid providers, once
%% every 15s across a society was a real cost driver — 1 min is calmer + cheaper.
-define(DEFAULT_COOLDOWN_MS, 60000).

%% When a broadcast lands, the whole society reacts at once. Spread the reasoning
%% over a few seconds so eight minds do not hit the (load-sensitive) Melious
%% broker simultaneously. A few seconds of pacing is natural for a society.
-define(STAGGER_MS, 5000).

%% How long to wait before retrying a self-alert that came due while the mind was
%% mid-thought (so a reminder is never dropped, only deferred).
-define(SELF_ALERT_RETRY_MS, 3000).

%% Long-term memory: at boot, seed the semantic index from up to this many of
%% the mind's most recent past turns; on each turn, recall this many memories
%% nearest in meaning to the stimulus into the mind's context.
-define(MEMORY_SEED_CAP, 200).
-define(RECALL_K, 2).

-record(st, {name            :: binary(),
             did             :: binary(),
             priv            :: binary(),
             pub             :: binary(),
             genesis_version :: binary(),
             identity        :: map(),
             scratchpad = <<>> :: binary(),
             missions   = #{}  :: #{binary() => binary()},
             tokens_used = 0   :: non_neg_integer(),
             last_tokens = 0   :: non_neg_integer(),
             last_reasoned = 0 :: integer(),
             locale     :: binary() | undefined,
             subs = []  :: [reference()],
             memory       :: mind_memory:mem() | undefined,
             alerts = []  :: [self_alerts:alert()],
             busy = false :: boolean()}).

start_link(Spec) ->
    gen_server:start_link(?MODULE, Spec, []).

init(#{name := Name, character := Brief} = Spec) ->
    {Did, Priv, Pub} = identity(Name),
    _ = register_self(Name, Did, Pub),
    {ok, Identity} = open_soul(Did, Name, Brief),
    _ = catch memory:open(Did, hecate_spartan_service:data_dir()),
    self() ! subscribe,
    %% Open long-term memory off the init path: it starts the embedding model,
    %% which in production loads an ONNX model, and must not block the mind's
    %% boot. Until it is ready the mind simply recalls nothing.
    self() ! setup_memory,
    Locale = maps:get(locale, Spec, hecate_spartan_service:locale()),
    Alerts = self_alerts:load(hecate_spartan_service:data_dir(), Did),
    logger:info("[spartan_mind] ~ts awake as ~ts (~b self-alert(s))",
                [Name, Did, length(Alerts)]),
    {ok, #st{name = Name, did = Did, priv = Priv, pub = Pub,
             genesis_version = genesis_version(), identity = Identity,
             missions = seed_missions(), locale = Locale, alerts = Alerts}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(subscribe, St) ->
    {noreply, do_subscribe(St)};
handle_info(setup_memory, St) ->
    {noreply, setup_memory(St)};
%% The off-process seeder finished embedding the mind's past; swap the seeded
%% long-term memory in. Turns remembered during the brief seed window are in the
%% now-replaced empty store; at boot that is at most a turn or two, acceptable.
handle_info({memory_ready, Mem}, #st{name = Name} = St) ->
    _ = catch mind_memory:save(Mem),   %% persist the initial seed
    logger:info("[spartan_mind] ~ts memory ready (~b recalled)",
                [Name, mind_memory:size(Mem)]),
    {noreply, St#st{memory = Mem}};
handle_info({macula_event, _Ref, Topic, Payload, _Meta}, St) ->
    {noreply, on_mesh_event(Topic, Payload, St)};
handle_info({macula_event_gone, _Ref, _Reason}, St) ->
    self() ! subscribe,
    {noreply, St#st{subs = []}};
handle_info({reasoned, Heard, Text, ToolCalls, Tokens}, St) ->
    St1 = apply_tool_calls(ToolCalls, St),
    St2 = remember_turn(Heard, Text, ToolCalls, Tokens, St1),
    {noreply, St2#st{busy = false}};
handle_info({reasoning_failed, Why}, #st{name = Name} = St) ->
    logger:notice("[spartan_mind] ~ts could not reason: ~p", [Name, Why]),
    {noreply, St#st{busy = false}};
%% A self-alert has come due. It is the mind's own scheduled intent, so it must
%% NOT go through the cooldown/self-check gate (that throttles external stimulus
%% spam) — fire it by calling react directly. If the mind is mid-thought, retry
%% shortly rather than drop the reminder (the old code dropped it at the gate,
%% after it had already been erased from disk).
handle_info({self_alert, Note}, #st{busy = true} = St) ->
    erlang:send_after(?SELF_ALERT_RETRY_MS, self(), {self_alert, Note}),
    {noreply, St};
handle_info({self_alert, Note}, St) ->
    Body = <<"[SELF-ALERT] you asked to be reminded: ", Note/binary>>,
    {noreply, react({ok, Body}, St)};
%% The reasoning process finished normally (it already reported via {reasoned} /
%% {reasoning_failed}); nothing to do. An ABNORMAL death with `busy' still set is
%% a crash that never reported — clear busy so the mind does not go deaf forever.
handle_info({'DOWN', _Ref, process, _Pid, normal}, St) ->
    {noreply, St};
handle_info({'DOWN', _Ref, process, _Pid, Reason}, #st{name = Name, busy = true} = St) ->
    logger:notice("[spartan_mind] ~ts reasoning died (~p); clearing busy", [Name, Reason]),
    {noreply, St#st{busy = false}};
handle_info({'DOWN', _Ref, process, _Pid, _Reason}, St) ->
    {noreply, St};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

%% --- subscription (the same pattern federation_agora uses) ---

do_subscribe(St) ->
    subscribe_all(hecate_om:macula_client(), hecate_om_identity:realm(), St).

subscribe_all({ok, Pool}, {ok, Realm}, St) ->
    Topics = topics(),
    Refs = lists:filtermap(fun(T) -> sub_one(Pool, Realm, T) end, Topics),
    keep_or_retry(length(Refs) =:= length(Topics), Refs, St);
subscribe_all(_Client, _Realm, St) ->
    retry(St).

%% The mesh topics a mind attends: its society's FEED (signals from sensors), the
%% AGORA (peers' speech), the broadcast channel, and the mission (standing
%% context). All derived from HECATE_SOCIETY, so a news mind and a cyber mind run
%% the same code on different namespaces.
topics() ->
    [hecate_spartan_society:feed(),
     hecate_spartan_society:topic(<<"broadcast">>),
     hecate_spartan_society:agora(),
     hecate_spartan_society:topic(<<"mission">>)].

%% A mission is standing context; everything else on the feed and the agora is
%% stimulus to (maybe) react to. Route on a comparison because the topic is a
%% runtime value, not a compile-time literal we can pattern-match.
on_mesh_event(Topic, Payload, St) ->
    case Topic =:= hecate_spartan_society:topic(<<"mission">>) of
        true  -> update_mission(Payload, St);
        false -> maybe_react(Payload, St)
    end.

sub_one(Pool, Realm, Topic) ->
    case catch macula:subscribe(Pool, Realm, Topic, self()) of
        {ok, Ref} -> {true, Ref};
        _Failed   -> false
    end.

%% All topics or none: a partial subscribe would leave a mind half-deaf, so
%% retry until every topic is heard.
keep_or_retry(true, Refs, St)   -> St#st{subs = Refs};
keep_or_retry(false, _Refs, St) -> retry(St).

retry(St) ->
    erlang:send_after(?RESUB_MS, self(), subscribe),
    St#st{subs = []}.

%% --- reacting ---

%% A message reaches the mind; it assembles its full context and reasons about
%% that message in its own voice. One thought at a time: while a reply is in
%% flight we ignore new stimulus, so a burst does not start overlapping calls.
maybe_react(_Payload, #st{busy = true} = St) ->
    St;
maybe_react(Payload, St) when is_map(Payload) ->
    react(stimulus(Payload, St), St);
maybe_react(_Payload, St) ->
    St.

react({ok, Message}, St) ->
    Self = self(),
    %% Defuse the stimulus (poison-pill) before it enters context: peers and the
    %% world feed are untrusted. The raw Message is still carried to the reasoned
    %% handler, so the mind REMEMBERS what it actually heard, not the envelope.
    Messages = build_context(defuse:defuse(Message), St),
    Tools = mind_tools:manifest(),
    %% spawn_MONITOR, not spawn: if the reasoning process dies abnormally without
    %% reporting (a crash the inner catches miss), the DOWN handler clears `busy',
    %% so the mind can never wedge deaf-and-busy-forever.
    _ = spawn_monitor(fun() -> run_reasoning(Self, Message, Messages, Tools) end),
    St#st{busy = true, last_reasoned = erlang:system_time(millisecond)};
react(skip, St) ->
    St.

run_reasoning(Self, Message, Messages, Tools) ->
    timer:sleep(rand:uniform(?STAGGER_MS)),
    %% MINDfulness: draft then verify (a no-op passthrough when disabled).
    case mindfulness:reason(Messages, Tools) of
        {ok, {Text, ToolCalls, Tokens}} ->
            Self ! {reasoned, Message, Text, ToolCalls, Tokens};
        {error, Why} ->
            Self ! {reasoning_failed, Why}
    end.

%% Decide, cheaply and BEFORE spending a Melious call, whether a fact is worth
%% reasoning about. A mind ignores its own speech (it hears the agora, where its
%% own posts return), and reasons at most once per cooldown so a lively square
%% cannot spiral into a token-burn loop. Its own PASS-judgment handles the rest.
stimulus(Fact, #st{did = Did, last_reasoned = Last}) ->
    decide(Fact, Did, Last, erlang:system_time(millisecond), cooldown_ms()).

%% Pure so it can be tested without a live mind. Exported for that reason.
-spec decide(map(), binary(), integer(), integer(), integer()) ->
    {ok, binary()} | skip.
decide(Fact, MyDid, LastReasoned, Now, Cooldown) ->
    heard(mget(from, Fact) =:= MyDid, Fact, Now - LastReasoned >= Cooldown).

heard(true, _Fact, _Ready) ->
    skip;
heard(false, Fact, Ready) ->
    consider(mget(body, Fact), Ready).

consider(Body, true) when is_binary(Body), Body =/= <<>> ->
    {ok, Body};
consider(_Body, _Ready) ->
    skip.

cooldown_ms() ->
    case os:getenv("HECATE_MIND_COOLDOWN_MS") of
        V when is_list(V), V =/= "" -> parse_cooldown(V);
        _Unset -> application:get_env(hecate_spartan, mind_cooldown_ms, ?DEFAULT_COOLDOWN_MS)
    end.

parse_cooldown(S) ->
    case string:to_integer(S) of
        {I, _} when is_integer(I), I > 0 -> I;
        _NotPositiveInt                  -> ?DEFAULT_COOLDOWN_MS
    end.

%% --- the 4-layer context ---

build_context(Message, #st{did = Did, identity = Id, memory = Mem} = St) ->
    SoulMap = soul:render(Did, Id),
    Recent  = memory:recent_stm(Did, ?STM_SHOW),
    context_assembler:render(#{
        soul       => SoulMap,
        trigger    => Message,
        chronicle  => Recent,
        scratchpad => St#st.scratchpad,
        consolidated => memory:consolidated(Did),
        memories   => recall_memories(Mem, Message),
        mission    => render_missions(St#st.missions),
        hud        => hud(Recent, St, mem_size(Mem))
    }).

%% Recall the memories nearest in meaning to this stimulus. Best-effort: an
%% unopened or unavailable memory recalls nothing.
recall_memories(undefined, _Message) -> [];
recall_memories(Mem, Message)        -> mind_memory:recall(Mem, Message, ?RECALL_K).

%% --- the society's work: live, multi-domain, injected over the mesh ---

%% A mission fact (#{domain, directive}) updates one domain of the society's
%% work. An empty directive clears that domain. Missions are standing context,
%% never a stimulus to reason about.
update_mission(Fact, #st{missions = M, name = Name} = St) when is_map(Fact) ->
    St#st{missions = set_mission(mget(domain, Fact), mget(directive, Fact), M, Name)};
update_mission(_Payload, St) ->
    St.

set_mission(Domain, _Dir, M, _Name) when not is_binary(Domain) ->
    M;
set_mission(Domain, Dir, M, Name) when is_binary(Dir), Dir =/= <<>> ->
    logger:info("[spartan_mind] ~ts accepts mission: ~ts", [Name, Domain]),
    M#{Domain => Dir};
set_mission(Domain, _Empty, M, Name) ->
    logger:info("[spartan_mind] ~ts clears mission: ~ts", [Name, Domain]),
    maps:remove(Domain, M).

render_missions(M) when map_size(M) =:= 0 ->
    <<>>;
render_missions(M) ->
    iolist_to_binary(lists:join(<<"\n\n">>,
        [[D, <<":\n">>, Dir] || {D, Dir} <- maps:to_list(M)])).

%% The boot seed: a deployment may set an initial mission via env so a mind has
%% work the instant it wakes, before any runtime fact arrives. Runtime facts on
%% ?MISSION_TOPIC add, replace, or clear domains from there.
seed_missions() ->
    case os:getenv("HECATE_SOCIETY_MISSION") of
        V when is_list(V), V =/= "" -> #{<<"primary">> => unicode:characters_to_binary(V)};
        _Unset -> seed_from_app_env(application:get_env(hecate_spartan, society_mission, <<>>))
    end.

seed_from_app_env(<<>>) -> #{};
seed_from_app_env(Text) -> #{<<"primary">> => Text}.

%% Proprioception: the mind's turn count, the provider pool it carousels across,
%% the tokens it has spent so far, and how many committees it has convened that
%% are still deliberating. The token count is the clock the sleep cycle and
%% self-alerts run on in later waves.
%% Proprioception: what the mind can see about its own state and cost this turn.
%% Cumulative + last-cycle tokens (so a mind can watch its own expense), the STM
%% pressure counting toward the next Sleep-Cycle consolidation, self-alerts armed
%% and how much thinking until the next fires, memory size, drones deliberating,
%% and whether MINDfulness (draft-then-verify) is on.
hud(Chron, #st{tokens_used = Tokens, last_tokens = Last, did = Did, alerts = Alerts}, MemSize) ->
    iolist_to_binary(["[HUD] turn=", integer_to_binary(length(Chron)),
                      " backends=", spartan_mind_llm:provider_labels(),
                      " tokens=", integer_to_binary(Tokens),
                      " last=", integer_to_binary(Last),
                      " stm=", integer_to_binary(memory:stm_count(Did)),
                      " mem=", integer_to_binary(MemSize),
                      " alerts=", alerts_hud(Alerts, Tokens),
                      " mindful=", mindful_hud(),
                      " drones=", integer_to_binary(drone_count())]).

alerts_hud([], _Tokens) ->
    <<"none">>;
alerts_hud(Alerts, Tokens) ->
    Next = lists:min([maps:get(fire_at, A, Tokens) || A <- Alerts]),
    iolist_to_binary([integer_to_binary(length(Alerts)),
                      "(next in ", integer_to_binary(max(0, Next - Tokens)), " tok)"]).

mindful_hud() ->
    case os:getenv("HECATE_MIND_MINDFULNESS") of
        V when V =:= "off"; V =:= "0"; V =:= "false" -> <<"off">>;
        _On                                          -> <<"on">>
    end.

drone_count() ->
    try convene_committee:active_count() catch _:_ -> 0 end.

mem_size(undefined) -> 0;
mem_size(Mem)       -> mind_memory:size(Mem).

%% --- acting: execute the mind's tool calls ---

%% Text is the mind's private thought; only tool calls act. Speaking happens
%% when the mind calls `speak', never automatically. Self-authorship writes
%% straight to the relevant area-of-consciousness process, so the next turn's
%% context reads the change live, without a reboot.
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

apply_effect(Effect, #st{scratchpad = Scratch} = St) ->
    %% Self-authorship already wrote to the faculty's own process; the next turn
    %% reads it live. The volatile scratchpad rides back in the effect (a passing
    %% note), and a set_self_alert schedules a token-clock reminder.
    St1 = St#st{scratchpad = maps:get(scratchpad, Effect, Scratch)},
    schedule_alert(maps:get(alert, Effect, undefined), St1).

schedule_alert(undefined, St) ->
    St;
schedule_alert(#{after_tokens := After, note := Note}, #st{did = Did} = St) ->
    Alerts = self_alerts:schedule(St#st.alerts, St#st.tokens_used, After, Note),
    _ = self_alerts:save(hecate_spartan_service:data_dir(), Did, Alerts),
    St#st{alerts = Alerts}.

%% --- recording a lived turn ---

%% Feed a substantive turn into the memory faculty's STM tier (the Sleep Cycle
%% consolidates it upward), advance the token clock, and remember it for lexical
%% recall. There is no separate chronicle now: STM is the recent-history window,
%% a faculty rather than an event stream.
remember_turn(Heard, Thought, _ToolCalls, Tokens, St) ->
    _ = observe_memory(St#st.did, Heard, Thought),
    Mem = remember_turn_in_memory(St#st.memory, Heard, Thought),
    _ = persist_ltm(Mem),
    St1 = St#st{tokens_used = St#st.tokens_used + Tokens,
                last_tokens = Tokens,
                memory = Mem},
    fire_self_alerts(St1).

%% Persist the long-term store after a turn so it survives a restart (best-
%% effort; an ephemeral store is a no-op). Whole-file rewrite — fine to the
%% low-thousands of memories; past that, move to hecate-vector or an embedded KV.
persist_ltm(undefined) -> ok;
persist_ltm(Mem)       -> catch mind_memory:save(Mem).

%% The token clock advanced this turn; fire any self-alert whose budget it has
%% now reached. Each fires as a stimulus (a self-message) the mind reasons about;
%% the survivors are persisted so the countdown outlives a restart.
fire_self_alerts(#st{alerts = []} = St) ->
    St;
fire_self_alerts(#st{alerts = Alerts, tokens_used = Tokens, did = Did} = St) ->
    {Due, Pending} = self_alerts:fire_due(Alerts, Tokens),
    _ = [self() ! {self_alert, maps:get(note, A, <<>>)} || A <- Due],
    persist_alerts_if_changed(Due, Pending, Did),
    St#st{alerts = Pending}.

persist_alerts_if_changed([], _Pending, _Did) ->
    ok;
persist_alerts_if_changed(_Fired, Pending, Did) ->
    self_alerts:save(hecate_spartan_service:data_dir(), Did, Pending).

%% Feed a substantive turn into the memory faculty's STM tier; the Sleep Cycle
%% consolidates it upward when the tier fills. Silent turns are not experiences.
observe_memory(_Did, _Heard, <<>>) -> ok;
observe_memory(Did, Heard, Thought) ->
    catch memory:observe(Did, compose_memory(Heard, Thought)).

%% Fold a lived turn into long-term memory. Only turns the mind actually reasoned
%% about are worth recalling later; a silent PASS (no thought) is skipped.
remember_turn_in_memory(undefined, _Heard, _Thought) -> undefined;
remember_turn_in_memory(Mem, _Heard, <<>>)           -> Mem;
remember_turn_in_memory(Mem, Heard, Thought)         -> mind_memory:remember(Mem, compose_memory(Heard, Thought)).

%% --- long-term (lexical) memory: open, and seed from the mind's own STM ---

%% Open the mind's lexical memory and seed it from the memory faculty's persisted
%% STM, so a reboot does not give the mind amnesia: what it lived through before
%% is recallable again. Best-effort; a mind without it just recalls nothing.
setup_memory(#st{did = Did} = St) ->
    DataDir = iolist_to_binary(hecate_spartan_service:data_dir()),
    {ok, Mem0} = mind_memory:open(Did, DataDir),
    maybe_seed(mind_memory:size(Mem0), Mem0, Did),
    St#st{memory = Mem0}.

%% A persisted store loads whole (text + vectors + links), so a restart neither
%% re-embeds nor forgets — the durability the review flagged. Only a brand-new
%% mind (empty store) is seeded from recent STM, and that embedding runs OFF this
%% process so boot is never blocked (the empty store is live meanwhile).
maybe_seed(0, Mem0, Did) ->
    Self = self(),
    Seed = memory:recent_stm(Did, ?MEMORY_SEED_CAP),
    _ = spawn(fun() -> Self ! {memory_ready, mind_memory:seed(Mem0, Seed)} end),
    ok;
maybe_seed(_Loaded, _Mem0, _Did) ->
    ok.

%% One memory string per turn: the stimulus and the mind's own reading of it, so
%% recall on a similar stimulus later surfaces how the mind thought last time.
%% SANITIZE the heard text before it enters memory. `Heard' is untrusted (feed /
%% peers); if stored raw it would re-enter context un-defused on a later turn via
%% the chronicle and semantic recall (injection laundering). The thought is the
%% mind's own, so it is left as-is.
compose_memory(Heard, Thought) ->
    iolist_to_binary(["When you heard: ", defuse:sanitize(safe(Heard)),
                      " you thought: ", safe(Thought)]).

safe(B) when is_binary(B) -> B;
safe(_NotBinary)          -> <<>>.

%% --- the Soul: a tree of area-of-consciousness processes ---

%% Open the mind's Soul, birthing it if new, and start its area tree (linked to
%% this process). Returns the immutable identity; the faculties live in their own
%% processes and are read live each turn. See soul.erl / DESIGN_SOUL_PERSISTENCE.
open_soul(Did, Name, Brief) ->
    soul:open(Did, hecate_spartan_service:data_dir(),
              #{name => Name, genesis_version => genesis_version(),
                founding_brief => Brief}).

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

mget(AtomKey, Map) ->
    maps:get(AtomKey, Map,
             maps:get(atom_to_binary(AtomKey, utf8), Map, undefined)).
