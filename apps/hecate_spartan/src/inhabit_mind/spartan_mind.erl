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
-export([decide/2, kind_of/3]).   %% the pre-LLM engagement gate, pure, exported for tests
-export([hold/2, pop_held/2]).    %% what a busy mind keeps for later, pure, exported for tests
-export([heard_new/0, heard_add/2, heard_has/2]).   %% hearing a post once, pure, exported for tests
-export([thread_cap/0, synthesizer/0, reply_cooldown_ms/0]).
-export([news_signals/1]).   %% structured stimulus signal, pure, exported for tests
-export([feed_topics/0]).   %% a mind's configured feed subscription, pure, exported for tests

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
%% Voices per story before it closes. See thread_cap/0.
-define(DEFAULT_THREAD_CAP, 4).
%% A peer's reply runs on a much shorter clock than a story opening: long
%% enough that two minds cannot volley, short enough that a conversation is
%% still a conversation. See clocked/3.
-define(DEFAULT_REPLY_COOLDOWN_MS, 30000).
%% A post older than this when it arrives is history being said again, not
%% speech. federation_agora says every instance's recent posts again once a
%% minute so a late joiner can fill its square; those carry `replay', and the
%% age catches the same posts from a peer on an older version.
-define(HISTORY_MS, 600_000).
%% Peer posts kept while the mind is busy or on its reply clock: one per
%% story, this many stories, and dropped unanswered once this old.
-define(HOLD_MAX, 8).
-define(HOLD_MAX_AGE_MS, 900_000).
%% How many post ids a mind remembers having heard, so a post said twice --
%% republished, or handed over by two stations -- is heard once.
-define(HEARD_MAX, 512).

%% When a broadcast lands, the whole society reacts at once. Spread the reasoning
%% over a few seconds so eight minds do not hit the (load-sensitive) Melious
%% broker simultaneously. A few seconds of pacing is natural for a society.
-define(STAGGER_MS, 5000).

%% How long to wait before retrying a self-alert that came due while the mind was
%% mid-thought (so a reminder is never dropped, only deferred).
-define(SELF_ALERT_RETRY_MS, 3000).

%% Long-term memory: at boot, seed the semantic index from up to this many of
%% the mind's most recent past turns; on each turn, recall the mind's own
%% memory_recall_k (mind_tunables.erl; defaults to 2, retunable per mind)
%% nearest-in-meaning memories into its context.
-define(MEMORY_SEED_CAP, 200).
%% Re-link one memory via the LLM every this-many remembered turns (~one sleep
%% consolidation window), so agentic linking costs one small call, not one/turn.
-define(EVOLVE_EVERY, 8).

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
             %% Two clocks, one per kind of turn: when this mind last opened a
             %% story (or reasoned unprompted) and when it last answered a
             %% peer. See clocked/3 for why they are not one.
             last_opened  = 0 :: integer(),
             last_replied = 0 :: integer(),
             %% Post ids heard, bounded, so a post said twice is heard once.
             heard        :: {queue:queue(), sets:set()} | undefined,
             %% Peers' replies kept while busy or on the reply clock, newest
             %% per story. See hold/2.
             held = #{}   :: #{binary() => map()},
             hold_timer   :: reference() | undefined,
             %% The peer post this turn answers, so `speak' can link to it
             %% when the model names no post itself.
             replying_to  :: binary() | undefined,
             locale     :: binary() | undefined,
             subs = []  :: [reference()],
             memory       :: mind_memory:mem() | undefined,
             since_evolve = 0 :: non_neg_integer(),
             %% Bumped on every remembered turn. The off-process evolver carries
             %% the version it started from, so a result computed against a stale
             %% snapshot is discarded instead of dropping a turn.
             mem_version = 0 :: non_neg_integer(),
             evolver      :: pid() | undefined,
             alerts = []  :: [self_alerts:alert()],
             %% What this mind is reasoning about RIGHT NOW, held across the
             %% turn so that if the mind decides to speak, its post can carry
             %% what it was reacting to. Set on every react, so an unprompted
             %% turn (a self-alert, a committee) clears it rather than citing
             %% the previous turn's news item. See `agora_stimulus'.
             stimulus     :: agora_stimulus:stimulus() | undefined,
             %% `synthesis' while this turn is a closing word, so `speak' marks
             %% the post as one. Cleared on every ordinary react.
             kind         :: synthesis | undefined,
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
    %% Same reasoning: citizen_register is a real mesh RPC round-trip
    %% (citizen_registration:register/3), not the local, in-process
    %% register_self/3 call above -- it must not block boot either.
    self() ! citizen_register,
    Locale = maps:get(locale, Spec, hecate_spartan_service:locale()),
    Alerts = self_alerts:load(hecate_spartan_service:data_dir(), Did),
    logger:info("[spartan_mind] ~ts awake as ~ts (~b self-alert(s))",
                [Name, Did, length(Alerts)]),
    {ok, #st{name = Name, did = Did, priv = Priv, pub = Pub,
             genesis_version = genesis_version(), identity = Identity,
             missions = seed_missions(), locale = Locale, alerts = Alerts,
             heard = heard_new()}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(subscribe, St) ->
    {noreply, do_subscribe(St)};
handle_info(setup_memory, St) ->
    {noreply, setup_memory(St)};
%% Register (or refresh) this mind's presence in the shared citizens
%% directory, then reschedule itself -- same self-rescheduling shape as
%% the self-alert retry below. citizen_registration:register/3 never
%% crashes (dark mesh / rejected proof both just log and return ok), so
%% this never needs its own retry-sooner path the way self_alert does.
handle_info(citizen_register, #st{name = Name, priv = Priv, pub = Pub} = St) ->
    _ = citizen_registration:register(Name, Priv, Pub),
    erlang:send_after(citizen_registration:reregister_ms(), self(), citizen_register),
    {noreply, St};
%% The off-process seeder finished embedding the mind's past; swap the seeded
%% long-term memory in. Turns remembered during the brief seed window are in the
%% now-replaced empty store; at boot that is at most a turn or two, acceptable.
handle_info({memory_ready, Mem}, #st{name = Name} = St) ->
    _ = catch mind_memory:save(Mem),   %% persist the initial seed
    logger:info("[spartan_mind] ~ts memory ready (~b recalled)",
                [Name, mind_memory:size(Mem)]),
    {noreply, St#st{memory = Mem}};
%% The evolver worked on a SNAPSHOT. If the mind remembered anything while it
%% ran, applying its result would silently drop that turn, so discard it; the
%% cadence counter is still high, so it retries on the next turn.
handle_info({evolved, Mem, V}, #st{mem_version = V} = St) ->
    _ = persist_ltm(Mem),
    {noreply, St#st{memory = Mem, since_evolve = 0, evolver = undefined}};
handle_info({evolved, _Stale, _V}, St) ->
    {noreply, St#st{evolver = undefined}};
handle_info({macula_event, _Ref, Topic, Payload, _Meta}, St) ->
    {noreply, on_mesh_event(Topic, Payload, St)};
handle_info({macula_event_gone, _Ref, _Reason}, St) ->
    self() ! subscribe,
    {noreply, St#st{subs = []}};
handle_info({reasoned, Heard, Text, ToolCalls, Tokens}, St) ->
    St1 = apply_tool_calls(ToolCalls, St),
    St2 = remember_turn(Heard, Text, ToolCalls, Tokens, St1),
    %% `kind' belongs to the turn, never to the mind: a closing word must not
    %% make every later post a conclusion too. The turn is over: take up
    %% whatever a peer said meanwhile.
    {noreply, resume(St2#st{busy = false, kind = undefined})};
handle_info({reasoning_failed, Why}, #st{name = Name} = St) ->
    logger:notice("[spartan_mind] ~ts could not reason: ~p", [Name, Why]),
    {noreply, resume(St#st{busy = false})};
%% The reply clock a held peer post was waiting on has run out.
handle_info(resume_held, #st{busy = true} = St) ->
    {noreply, St#st{hold_timer = undefined}};
handle_info(resume_held, St) ->
    {noreply, resume(St#st{hold_timer = undefined})};
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
    %% A self-alert is the mind's own intent, not a sensed fact — no signal line.
    {noreply, start_turn(Body, other, #{}, St)};
%% The reasoning process finished normally (it already reported via {reasoned} /
%% {reasoning_failed}); nothing to do. An ABNORMAL death with `busy' still set is
%% a crash that never reported — clear busy so the mind does not go deaf forever.
%% The evolver dying must NOT be mistaken for the reasoner dying: the clauses
%% below clear `busy', and clearing it because a background evolve crashed would
%% let a second thought start while the first is still in flight.
handle_info({'DOWN', _Ref, process, Pid, _Reason}, #st{evolver = Pid} = St) ->
    {noreply, St#st{evolver = undefined}};
handle_info({'DOWN', _Ref, process, _Pid, normal}, St) ->
    {noreply, St};
handle_info({'DOWN', _Ref, process, _Pid, Reason}, #st{name = Name, busy = true} = St) ->
    logger:notice("[spartan_mind] ~ts reasoning died (~p); clearing busy", [Name, Reason]),
    {noreply, resume(St#st{busy = false})};
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
    feed_topics() ++
    [hecate_spartan_society:topic(<<"broadcast">>),
     hecate_spartan_society:agora(),
     hecate_spartan_society:topic(<<"mission">>)].

%% A mind's news-feed subscription: the firehose by default, or specific
%% category sub-topics (HECATE_MIND_FEED_TOPICS) for real informational
%% asymmetry between minds — not just different persona text reacting to
%% identical input (see hecate-spartan/insights/001: "different adjectives
%% is cosplay"). The sensor side publishes each item to <ns>/feed AND to
%% <ns>/feed/<axis>/<value> per axis it carries a value for (hecate-news);
%% this just picks which of those a mind subscribes to.
%%
%% "source_type:broadcaster,country:de,country:at" subscribes to THREE
%% topics — one per clause — so a mind hears the UNION of matching items,
%% not their intersection: combining axes widens the diet, it does not
%% narrow it. A repeated axis (two country clauses, as above) is exactly
%% that widening within one axis.
feed_topics() ->
    resolved_feed_topics(feed_axes()).

resolved_feed_topics([]) ->
    [hecate_spartan_society:feed()];
resolved_feed_topics(Axes) ->
    [hecate_spartan_society:topic(<<"feed/", Axis/binary, "/", Value/binary>>)
     || {Axis, Value} <- Axes].

feed_axes() ->
    parse_feed_axes(os:getenv("HECATE_MIND_FEED_TOPICS")).

parse_feed_axes(false) -> [];
parse_feed_axes("")    -> [];
parse_feed_axes(Env) ->
    Bin = unicode:characters_to_binary(Env),
    lists:filtermap(fun parse_axis/1, binary:split(Bin, <<",">>, [global])).

parse_axis(Clause) ->
    interpret_axis(binary:split(string:trim(Clause), <<":">>)).

interpret_axis([Axis, Value]) when Axis =/= <<>>, Value =/= <<>> ->
    known_axis(existing_axis(string:trim(Axis)), string:trim(Value));
interpret_axis(_Malformed) ->
    false.

known_axis(undefined, _Value) -> false;
known_axis(Axis, Value)       -> {true, {Axis, Value}}.

%% Whitelist, matching hecate-news's own three published axes — an unknown
%% axis name is a config typo, not a topic to subscribe to.
existing_axis(<<"source_type">>) -> <<"source_type">>;
existing_axis(<<"country">>)     -> <<"country">>;
existing_axis(<<"topic_class">>) -> <<"topic_class">>;
existing_axis(_Unknown)          -> undefined.

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

%% Everything a mind hears comes through here, and the first question is not
%% "may I reason about this" but "have I heard this before". A post arrives
%% many times: federation_agora says every instance's recent speech again once
%% a minute so a late joiner can fill its square, and a subscriber dialling
%% three stations can be handed one fact by more than one of them. Measured on
%% 2026-09-03: one peer post reached every other mind about forty times in
%% forty minutes, each arrival treated as new and each one competing for the
%% single turn the cooldown allows. Ninety-five percent of what a mind heard
%% was something it had already heard, and the turn went to whichever copy
%% came first. Hear a post once, and treat history as history.
maybe_react(Payload, #st{did = Did} = St) when is_map(Payload) ->
    arrival(kind_of(Payload, Did, now_ms()), Payload, St);
maybe_react(_Payload, St) ->
    St.

%% Its own post coming back round the agora. Nothing was missed — it already
%% knows what it said — so note the decline but do not re-observe it.
arrival(own, _Fact, #st{did = Did} = St) ->
    _ = mind_journal:append(Did, stimulus_declined_v1, #{reason => own_speech}),
    St;
%% History being said again fills nothing here: the square's own table is
%% federation_agora's to keep. It is remembered as heard so that the SAME post,
%% arriving later without the flag, is still not news.
arrival(replay, Fact, St) ->
    remember_heard(post_id(Fact), St);
arrival(peer, Fact, St) ->
    once(heard_has(post_id(Fact), St#st.heard), Fact, St);
arrival(Kind, Fact, St) ->
    consider(Kind, Fact, St).

once(true, _HeardAlready, St) ->
    St;
once(false, Fact, St) ->
    consider(peer, Fact, remember_heard(post_id(Fact), St)).

%% One thought at a time. While a turn is in flight a story opening is let go
%% (there will be another; they arrive by the minute) and journalled as never
%% reasoned about, but a peer's reply is KEPT: a reply that lands during the
%% twenty seconds a turn takes is the whole conversation, and dropping it is
%% why no mind here had ever answered another.
consider(peer, Fact, #st{busy = true} = St) ->
    keep(Fact, St);
consider(_Kind, Fact, #st{busy = true} = St) ->
    let_go(busy, Fact, St);
consider(Kind, Fact, St) ->
    react(decide(Fact, gate(Kind, Fact, St)), Kind, Fact, St).

react({ok, Message}, Kind, Fact, St) ->
    start_turn(Message, Kind, Fact, St);
%% A FULL THREAD is the synthesizer's cue, not merely a decline. Every other
%% mind steps back; the one mind whose job it is writes the closing word, and
%% the story is finished rather than abandoned. Without this a thread just
%% stops, which is what the record has always looked like.
react({declined, thread_full}, _Kind, Fact, #st{did = Did} = St) ->
    _ = mind_journal:append(Did, stimulus_declined_v1, #{reason => thread_full}),
    maybe_close(closable(Fact, St), Fact, St);
%% On the reply clock: keep it, and come back to it the moment the clock allows.
react({declined, reply_cooldown}, peer, Fact, St) ->
    resume_later(keep(Fact, St));
react({declined, Reason}, _Kind, Fact, St) ->
    let_go(Reason, Fact, St).

%% DEFECT 3. A stimulus the mind was too busy or too recently-woken to reason
%% about used to vanish entirely: it never entered STM, so the mind's own record
%% of what it lived through was a biased sample — whatever happened to arrive at a
%% quiet moment. Gene accumulates every observation whether or not a call fires
%% (spartan.py:3408-3444). Record it, cheaply, with no LLM.
let_go(Reason, Fact, #st{did = Did} = St) ->
    _ = mind_journal:append(Did, stimulus_declined_v1, #{reason => Reason}),
    _ = catch memory:observe(Did, unheard(mget(body, Fact))),
    St.

start_turn(Message, Kind, Fact, #st{did = Did} = St) ->
    Self = self(),
    %% Defuse the stimulus (poison-pill) before it enters context: peers and the
    %% world feed are untrusted. The raw Message is still carried to the reasoned
    %% handler, so the mind REMEMBERS what it actually heard, not the envelope.
    %% The signal line is the sensor's structured metadata (closed vocabulary),
    %% carried alongside so the mind reasons on WHAT/WHERE/WHO, not prose alone.
    Messages = build_context(defuse:defuse(Message), news_signals(Fact), St),
    Tools = mind_tools:manifest(Did),
    %% spawn_MONITOR, not spawn: if the reasoning process dies abnormally without
    %% reporting (a crash the inner catches miss), the DOWN handler clears `busy',
    %% so the mind can never wedge deaf-and-busy-forever.
    _ = spawn_monitor(fun() -> run_reasoning(Self, Did, Message, Messages, Tools) end),
    clocked(Kind, Fact,
            St#st{busy = true,
                  %% A closing turn arrives with its stimulus and kind already
                  %% set (see close_with/4) and an empty Fact, so do not
                  %% overwrite them.
                  stimulus = carried(agora_stimulus:of_fact(Fact), St#st.stimulus)}).

%% TWO CLOCKS. Opening a story and answering a peer are not the same act and
%% do not share a budget. Openings arrive by the minute and are rationed by
%% the cooldown, which is the cost brake. A reply is bounded by the thread
%% itself (the cap, the novelty gate, the closing word), so it runs on a clock
%% short enough to keep a conversation alive and long enough to stop two minds
%% volleying. A closing word is neither and touches neither.
clocked(peer, Fact, St) ->
    St#st{last_replied = now_ms(), replying_to = post_id(Fact)};
clocked(closing, _Fact, St) ->
    St#st{replying_to = undefined};
clocked(_OpeningOrOther, _Fact, St) ->
    St#st{last_opened = now_ms(), replying_to = undefined}.

%% --- holding a peer's reply until the mind can take it up ---

keep(Fact, #st{held = Held} = St) ->
    St#st{held = hold(Fact, Held)}.

%% @doc Keep a peer post for later: the newest per story, a bounded number of
%% stories, the oldest story let go when there are too many. Pure.
-spec hold(map(), #{binary() => map()}) -> #{binary() => map()}.
hold(Fact, Held) ->
    Key = story_key(Fact),
    bounded(Held#{Key => newer(Fact, maps:get(Key, Held, undefined))}).

newer(Fact, undefined) ->
    Fact;
newer(Fact, Kept) ->
    latest(posted(Fact) >= posted(Kept), Fact, Kept).

latest(true, Fact, _Kept) -> Fact;
latest(false, _Fact, Kept) -> Kept.

bounded(Held) when map_size(Held) =< ?HOLD_MAX ->
    Held;
bounded(Held) ->
    [{Oldest, _} | _] = lists:sort(fun by_posted/2, maps:to_list(Held)),
    maps:remove(Oldest, Held).

by_posted({_, A}, {_, B}) -> posted(A) =< posted(B).

%% A story is its own thread; unprompted speech is a thread of one.
story_key(Fact) ->
    key_of(agora_stimulus:of_fact(Fact), Fact).

key_of(#{item_id := ItemId}, _Fact) -> ItemId;
key_of(undefined, Fact)             -> post_id(Fact).

posted(Fact) ->
    whole(mget(posted_at, Fact)).

whole(N) when is_integer(N) -> N;
whole(_NotANumber)          -> 0.

%% @doc The held post to take up next (the newest), the rest, and the ones
%% that grew too old to be worth answering. Pure.
-spec pop_held(#{binary() => map()}, integer()) -> {map() | none, #{binary() => map()}, [map()]}.
pop_held(Held, Now) ->
    {Live, Expired} = lists:partition(fun({_, F}) -> Now - posted(F) =< ?HOLD_MAX_AGE_MS end,
                                      maps:to_list(Held)),
    next(lists:reverse(lists:sort(fun by_posted/2, Live)), [F || {_, F} <- Expired]).

next([], Expired)                -> {none, #{}, Expired};
next([{_, Fact} | Rest], Expired) -> {Fact, maps:from_list(Rest), Expired}.

%% After a turn, or when the reply clock runs out: take up what was held,
%% one at a time, until a turn starts or nothing is left. What grew too old
%% while waiting is let go the way an opening that arrived mid-turn is.
resume(#st{held = Held} = St) when map_size(Held) =:= 0 ->
    St;
resume(St) ->
    settle(step(St)).

settle(#st{busy = true} = St)                       -> St;
settle(#st{hold_timer = T} = St) when T =/= undefined -> St;
settle(St)                                          -> resume(St).

step(#st{held = Held} = St) ->
    {Next, Rest, Expired} = pop_held(Held, now_ms()),
    St1 = lists:foldl(fun(F, S) -> let_go(expired_hold, F, S) end, St#st{held = Rest}, Expired),
    take_up(Next, St1).

take_up(none, St) -> St;
take_up(Fact, St) -> consider(peer, Fact, St).

resume_later(#st{hold_timer = undefined, last_replied = Last} = St) ->
    Wait = max(1000, reply_cooldown_ms() - (now_ms() - Last)),
    St#st{hold_timer = erlang:send_after(Wait, self(), resume_held)};
resume_later(St) ->
    St.

%% --- hearing a post once ---

-spec heard_new() -> {queue:queue(), sets:set()}.
heard_new() ->
    {queue:new(), sets:new([{version, 2}])}.

-spec heard_has(binary() | undefined, {queue:queue(), sets:set()}) -> boolean().
heard_has(undefined, _Heard)  -> false;
heard_has(Id, {_Order, Set}) -> sets:is_element(Id, Set).

-spec heard_add(binary() | undefined, {queue:queue(), sets:set()}) -> {queue:queue(), sets:set()}.
heard_add(undefined, Heard) ->
    Heard;
heard_add(Id, {Order, Set}) ->
    forget_oldest({queue:in(Id, Order), sets:add_element(Id, Set)}).

forget_oldest({Order, Set} = Heard) ->
    forget(queue:len(Order) > ?HEARD_MAX, Heard, Set).

forget(false, Heard, _Set) ->
    Heard;
forget(true, {Order, _}, Set) ->
    {{value, Oldest}, Rest} = queue:out(Order),
    {Rest, sets:del_element(Oldest, Set)}.

remember_heard(Id, #st{heard = Heard} = St) ->
    St#st{heard = heard_add(Id, Heard)}.

post_id(Fact) ->
    id_or_none(mget(post_id, Fact)).

id_or_none(Id) when is_binary(Id), Id =/= <<>> -> Id;
id_or_none(_NoId)                              -> undefined.

now_ms() ->
    erlang:system_time(millisecond).

%% Whether THIS mind should close THIS story now: it is the synthesizer, the
%% story is real, and nobody has closed it yet.
closable(Fact, #st{busy = Busy}) ->
    closable_story(synthesizer(), Busy, agora_stimulus:of_fact(Fact)).

closable_story(true, false, #{item_id := ItemId} = Stimulus) ->
    unclosed(catch hecate_spartan_agora:closed(ItemId), Stimulus);
closable_story(_NotMine, _Busy, _Stimulus) ->
    false.

unclosed(false, Stimulus) -> {yes, Stimulus};
unclosed(_ClosedOrUnavailable, _Stimulus) -> false.

maybe_close(false, _Fact, St) ->
    St;
maybe_close({yes, Stimulus}, _Fact, #st{did = Did} = St) ->
    Thread = catch hecate_spartan_agora:thread(maps:get(item_id, Stimulus)),
    close_with(Thread, Stimulus, Did, St).

close_with(Thread, Stimulus, _Did, St) when is_list(Thread), Thread =/= [] ->
    %% Reasoned like any other turn, but from a different brief and marked on
    %% the way out (`kind = synthesis'), so a reader and a consumer can both
    %% tell a conclusion from another opinion without parsing prose.
    start_turn(closing_brief(Thread, Stimulus), closing, #{},
               St#st{stimulus = Stimulus, kind = synthesis});
close_with(_NoThread, _Stimulus, _Did, St) ->
    St.

%% The whole thread, and the one instruction that is not "have an opinion".
closing_brief(Thread, Stimulus) ->
    Said = [<<"\n- ", (defuse:sanitize(maps:get(body, P, <<>>)))/binary>> || P <- Thread],
    iolist_to_binary(
      [<<"[CLOSE] This story has had its voices and is now yours to end. "
         "Story: ">>, defuse:sanitize(maps:get(title, Stimulus, <<>>)),
       <<"\n\nWhat the society said:">>, Said,
       <<"\n\nWrite the CONCLUSION: what was actually established, where the "
         "society divided and on what, and what remains open. Do not add a new "
         "opinion of your own and do not restate the takes one by one. If "
         "nothing was established, say that plainly -- it is a finding.">>]).

%% @doc Whether this mind is the one that closes threads.
%%
%% One per society. `HECATE_MIND_SYNTHESIZER=1' on exactly one node: two
%% synthesizers would each close every thread and the square would end twice.
-spec synthesizer() -> boolean().
synthesizer() ->
    lists:member(os:getenv("HECATE_MIND_SYNTHESIZER"), ["1", "true", "yes"]).

carried(undefined, Carried) -> Carried;
carried(Sensed, _Carried)    -> Sensed.

%% Marked, so that when the mind next reads its recent history it can see this
%% arrived while it was occupied and was never reasoned about.
unheard(Body) when is_binary(Body), Body =/= <<>> ->
    <<"(unreasoned, arrived while occupied) ", (defuse:sanitize(Body))/binary>>;
unheard(_NotText) ->
    <<>>.

%% The structured signal a sensor attached to a fact: topic class, who reported it
%% (country + source type), where it is about. A closed-vocabulary line the mind
%% reasons and routes on. Empty for peer speech (agora/broadcast carry no sensor
%% metadata). Sanitized as defence in depth even though the vocabulary is ours.
news_signals(Fact) when is_map(Fact) ->
    Parts = [topic_sig(mget(topic_class, Fact, <<>>)),
             reporter_sig(mget(reporting_country_name, Fact, <<>>),
                          mget(source_type, Fact, <<>>)),
             subject_sig(mget(subject_country_name, Fact, <<>>))],
    join_signals([P || P <- Parts, P =/= <<>>]);
news_signals(_NotMap) ->
    <<>>.

topic_sig(<<>>)        -> <<>>;
topic_sig(<<"general">>) -> <<>>;
topic_sig(Class)       -> Class.

reporter_sig(<<>>, _Type) -> <<>>;
reporter_sig(Name, <<>>)  -> <<"reported by ", Name/binary>>;
reporter_sig(Name, Type)  -> <<"reported by ", Name/binary, " (", Type/binary, ")">>.

subject_sig(<<>>) -> <<>>;
subject_sig(Name) -> <<"about ", Name/binary>>.

join_signals([]) ->
    <<>>;
join_signals(Parts) ->
    defuse:sanitize(clip_sig(iolist_to_binary(lists:join(<<" · "/utf8>>, Parts)))).

clip_sig(Bin) -> clip_sig(Bin, string:length(Bin)).

clip_sig(Bin, Len) when Len =< 200 -> Bin;
clip_sig(Bin, _Len)                -> string:slice(Bin, 0, 200).

run_reasoning(Self, Did, Message, Messages, Tools) ->
    timer:sleep(rand:uniform(?STAGGER_MS)),
    %% MINDfulness: draft then verify (a no-op passthrough when disabled,
    %% whether disabled by the node's env var or the mind's own retune).
    case mindfulness:reason(Did, Messages, Tools) of
        {ok, {Text, ToolCalls, Tokens}} ->
            Self ! {reasoned, Message, Text, ToolCalls, Tokens};
        {error, Why} ->
            Self ! {reasoning_failed, Why}
    end.

%% --- the gate: what kind of thing was heard, and whether to reason about it ---

-type kind() :: own | replay | peer | opening | other | closing.
-type gate() :: #{kind := kind(), now := integer(),
                  last_opened := integer(), last_replied := integer(),
                  cooldown := pos_integer(), reply_cooldown := pos_integer(),
                  room := boolean()}.

%% @doc What a fact is to this mind. Pure; `Now' is passed in so history can
%% be told from speech without a clock.
%%
%% `own' is its own post coming back round the agora. `replay' is a peer's
%% post being said again (flagged by the republisher, or simply old enough
%% that it cannot be live speech). `peer' is a peer's fresh post. `opening'
%% is a sensor fact that opens a story (it carries a stimulus). `other' is
%% everything else: a broadcast, a self-alert, an empty map.
-spec kind_of(term(), binary(), integer()) -> kind().
kind_of(Fact, MyDid, Now) when is_map(Fact) ->
    classify(mget(from, Fact) =:= MyDid, post_id(Fact), Fact, Now);
kind_of(_NotAMap, _MyDid, _Now) ->
    other.

classify(true, _PostId, _Fact, _Now) ->
    own;
classify(false, undefined, Fact, _Now) ->
    opening_or_other(agora_stimulus:of_fact(Fact));
classify(false, _PostId, Fact, Now) ->
    peer_or_replay(replayed(mget(replay, Fact)) orelse stale(mget(posted_at, Fact), Now)).

opening_or_other(undefined) -> other;
opening_or_other(_Stimulus) -> opening.

peer_or_replay(true)  -> replay;
peer_or_replay(false) -> peer.

%% No booleans on the wire: the republisher marks history with `replay => 1'.
replayed(1)    -> true;
replayed(true) -> true;
replayed(_)    -> false.

stale(At, Now) when is_integer(At) -> Now - At > ?HISTORY_MS;
stale(_NoTime, _Now)               -> false.

gate(Kind, Fact, #st{last_opened = Opened, last_replied = Replied}) ->
    #{kind => Kind, now => now_ms(),
      last_opened => Opened, last_replied => Replied,
      cooldown => cooldown_ms(), reply_cooldown => reply_cooldown_ms(),
      room => thread_room(Fact)}.

%% @doc Decide, cheaply and BEFORE spending an LLM call, whether a fact is
%% worth reasoning about. Pure so it can be tested without a live mind.
%%
%% The decline carries its REASON, because the cases are not the same thing:
%% own speech was never missed, history was already heard, an empty body is
%% nothing, a full thread is the synthesizer's cue, a peer on the reply clock
%% is kept for later, and an opening declined on cooldown is real input the
%% mind never saw and must still record.
-spec decide(map(), gate()) ->
    {ok, binary()} |
    {declined, own_speech | replay | empty | thread_full | reply_cooldown | cooldown}.
decide(_Fact, #{kind := own}) ->
    {declined, own_speech};
decide(_Fact, #{kind := replay}) ->
    {declined, replay};
decide(Fact, Gate) ->
    weigh(mget(body, Fact), Gate).

%% BOUNDED THREADS. A story the society has already answered enough times is
%% closed to further reaction, which is the forward pressure the square has
%% never had: without a cap nothing ever ENDS, and a page of forty openings
%% with no endings is what the record looked like. The cap is checked before
%% either clock so a mind whose turn is up is not spent on a full thread.
weigh(Body, _Gate) when not is_binary(Body); Body =:= <<>> ->
    {declined, empty};
weigh(_Body, #{room := false}) ->
    {declined, thread_full};
weigh(Body, #{kind := peer, now := Now, last_replied := Last, reply_cooldown := Wait})
  when Now - Last >= Wait ->
    {ok, Body};
weigh(_Body, #{kind := peer}) ->
    {declined, reply_cooldown};
weigh(Body, #{now := Now, last_opened := Last, cooldown := Wait}) when Now - Last >= Wait ->
    {ok, Body};
weigh(_Body, _OnCooldown) ->
    {declined, cooldown}.

%% Whether this story still has room for another voice.
%%
%% Local, and it has to be: every instance hears the whole square, so each
%% counts from its own table with no RPC and nothing to keep in step. A fact
%% that is not about a story (a peer's unprompted post, a mission, a
%% self-alert) is never capped -- only stories are threads.
thread_room(Fact) ->
    room(agora_stimulus:of_fact(Fact)).

room(undefined) ->
    true;
room(#{item_id := ItemId}) ->
    catch_room(catch hecate_spartan_agora:thread_size(ItemId)).

catch_room(N) when is_integer(N) -> N < thread_cap();
%% No feed (early boot, or a test with no ETS table): never cap. Failing
%% closed here would silence a mind for a reason it could not see.
catch_room(_Unavailable)         -> true.

%% @doc How many times the society may speak about one story.
%%
%% Four, by default: enough for a claim, two answers and a correction, which
%% is a conversation; few enough that the square moves on. The synthesizer's
%% closing word is exempt (see `synthesizing/2'), so a full thread still gets
%% an ending.
-spec thread_cap() -> pos_integer().
thread_cap() ->
    parse_cap(os:getenv("HECATE_MIND_THREAD_CAP")).

parse_cap(V) when is_list(V), V =/= "" ->
    cap_of(string:to_integer(V));
parse_cap(_Unset) ->
    ?DEFAULT_THREAD_CAP.

cap_of({N, _}) when is_integer(N), N > 0 -> N;
cap_of(_NotAPositiveInteger)             -> ?DEFAULT_THREAD_CAP.

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

%% @doc How long after answering a peer a mind may answer one again.
%% Env-driven per node (HECATE_MIND_REPLY_COOLDOWN_MS), else app-env
%% `mind_reply_cooldown_ms', else thirty seconds.
-spec reply_cooldown_ms() -> pos_integer().
reply_cooldown_ms() ->
    case os:getenv("HECATE_MIND_REPLY_COOLDOWN_MS") of
        V when is_list(V), V =/= "" -> parse_reply_cooldown(string:to_integer(V));
        _Unset -> application:get_env(hecate_spartan, mind_reply_cooldown_ms,
                                      ?DEFAULT_REPLY_COOLDOWN_MS)
    end.

parse_reply_cooldown({I, _}) when is_integer(I), I > 0 -> I;
parse_reply_cooldown(_NotPositiveInt)                  -> ?DEFAULT_REPLY_COOLDOWN_MS.

%% --- the 4-layer context ---

build_context(Message, Signals, #st{did = Did, identity = Id, memory = Mem} = St) ->
    SoulMap = soul:render(Did, Id),
    Recent  = memory:recent_stm(Did, ?STM_SHOW),
    context_assembler:render(#{
        soul       => SoulMap,
        trigger    => Message,
        signals    => Signals,
        chronicle  => Recent,
        scratchpad => St#st.scratchpad,
        consolidated => memory:consolidated(Did),
        memories   => recall_memories(Mem, Message, Did),
        mission    => render_missions(St#st.missions),
        hud        => hud(Recent, St, mem_size(Mem))
    }).

%% Recall the memories nearest in meaning to this stimulus, as many as this
%% mind's own memory_recall_k (mind_tunables.erl). Best-effort: an unopened or
%% unavailable memory recalls nothing.
recall_memories(undefined, _Message, _Did) -> [];
recall_memories(Mem, Message, Did) ->
    mind_memory:recall(Mem, Message, mind_tunables:current(Did, memory_recall_k)).

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
                      " mindful=", mindful_hud(Did),
                      " drones=", integer_to_binary(drone_count())]).

alerts_hud([], _Tokens) ->
    <<"none">>;
alerts_hud(Alerts, Tokens) ->
    Next = lists:min([maps:get(fire_at, A, Tokens) || A <- Alerts]),
    iolist_to_binary([integer_to_binary(length(Alerts)),
                      "(next in ", integer_to_binary(max(0, Next - Tokens)), " tok)"]).

%% Reads the SAME effective value reasoning actually runs with (mindfulness's
%% own retune-then-env precedence), so a retune is visible on the very next HUD.
mindful_hud(Did) ->
    case mindfulness:enabled(Did) of
        true  -> <<"on">>;
        false -> <<"off">>
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

apply_tool_call(Call, #st{name = Name, did = Did, priv = Priv, pub = Pub,
                          stimulus = Stimulus} = St) ->
    Ctx = #{did => Did, priv => Priv, pub => Pub, stimulus => Stimulus,
            kind => St#st.kind, replying_to => St#st.replying_to},
    case mind_tools:execute(Call, Ctx) of
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
    Mem0 = remember_turn_in_memory(St#st.memory, Heard, Thought),
    N = St#st.since_evolve + 1,
    V = St#st.mem_version + 1,
    _ = persist_ltm(Mem0),
    St1 = St#st{tokens_used = St#st.tokens_used + Tokens,
                last_tokens = Tokens,
                since_evolve = N,
                mem_version = V,
                memory = Mem0},
    fire_self_alerts(start_evolve(due_to_evolve(N, St1), V, St1)).

%% Cadenced A-Mem evolution: every ?EVOLVE_EVERY remembered turns the LLM re-links
%% one memory (Gene's agentic linking).
%%
%% DEFECT 6: this ran INSIDE the mind's gen_server, with the full six-attempt
%% retry schedule, so every eighth turn the mind went deaf for the duration of an
%% extra LLM call — and, before defect 3 was fixed, everything that arrived
%% meanwhile was discarded rather than queued. It runs off-process now, exactly as
%% reasoning already does.
due_to_evolve(N, #st{evolver = undefined, memory = Mem}) ->
    N >= ?EVOLVE_EVERY andalso Mem =/= undefined;
due_to_evolve(_N, #st{}) ->
    false.

start_evolve(false, _V, St) ->
    St;
start_evolve(true, V, #st{memory = Mem} = St) ->
    Self = self(),
    {Pid, _Ref} = spawn_monitor(
        fun() -> Self ! {evolved, mind_memory:evolve(Mem, fun evolve_reason/1), V} end),
    St#st{evolver = Pid}.

evolve_reason(Msgs) -> ok_reply(catch spartan_mind_llm:reason_messages(Msgs)).

ok_reply({ok, Text}) when is_binary(Text) -> {ok, Text};
ok_reply(_Other)                          -> error.

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
    mget(AtomKey, Map, undefined).

%% A fact crosses the mesh as CBOR, so a key may arrive as an atom or a binary;
%% try both before the default.
mget(AtomKey, Map, Default) ->
    maps:get(AtomKey, Map,
             maps:get(atom_to_binary(AtomKey, utf8), Map, Default)).
