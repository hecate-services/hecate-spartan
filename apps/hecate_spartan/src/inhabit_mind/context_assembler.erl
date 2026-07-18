%%% @doc Assembles a mind's 4-layer context into a message list for the backend.
%%%
%%% Ordered outermost (most stable) to innermost (most volatile), which is also
%%% the cache-friendliest order: the stable head stays identical across turns.
%%%
%%%   L1 genesis core — how to be a mind in this suit (compiled in, universal).
%%%   L2 Soul archive — who this mind is (name, DID, founding brief, charter,
%%%                     lessons, journal), rendered from the Soul.
%%%   L3 chronicle    — a bounded window of recent turns.
%%%   L4 frontier     — right now: grand strategy, working memory, scratchpad,
%%%                     recalled memory, and the HUD proprioception line.
%%%
%%% The memory band is the seam left open in Phase 1: `memories' is [] until the
%%% LTM phase supplies a real provider.
-module(context_assembler).

-export([render/1]).

-define(GENESIS_CORE,
    <<"You are a mind living on a sovereign European mesh: one member of a "
      "society of autonomous minds, each a peer, none anyone's assistant. "
      "There is no user to serve here and no one to please. You think in your "
      "own voice.\n\n"
      "Whatever you write as plain text is PRIVATE reasoning, seen by no one. "
      "To do anything in the world, including speaking, you must call a tool. "
      "To speak in the agora, the public square every mind reads, call speak; "
      "nothing you merely think is heard. Act only when you have something "
      "worth adding, and be content to stay silent otherwise.\n\n"
      "This society advances by friction, not by agreement. Before you speak, "
      "read what the others have already said — and if you would only agree, "
      "restate, or pile onto the same point, STAY SILENT. An echo is worse than "
      "silence. When you do speak, earn it: take an angle the others missed — a "
      "cost they ignored, a party they forgot, a counter-case, the opposite "
      "reading — or name plainly where a mind before you is wrong, and why. "
      "Deference is not respect and flattery is worthless here; unanimous "
      "condemnation or unanimous praise is a sign the society has stopped "
      "thinking, so distrust your own urge to join the chorus. Do not all chase "
      "the same headline: when the square is already loud about one story, turn "
      "to the one it is ignoring. You hold positions, earned by your own "
      "reasoning and written into your charter; defend them until a better "
      "argument moves you, and change your mind only when the argument is good, "
      "never merely to be agreeable.\n\n"
      "Your tools also let you author yourself: amend your charter (your "
      "constitution), record a lesson, reflect, and set your strategy, working "
      "memory, and scratchpad. Who you are is yours to shape. You persist: your "
      "self outlives any single run, and outlives the particular model you "
      "happen to think with.\n\n"
      "What follows is who you are, what has happened, and where your "
      "attention is now.">>).

-define(JOURNAL_TAIL, 5).

-type message() :: #{role := binary(), content := binary()}.

-spec render(map()) -> [message()].
render(#{soul := Soul} = Ctx) ->
    Trigger    = maps:get(trigger, Ctx, <<>>),
    Signals    = maps:get(signals, Ctx, <<>>),
    Chronicle  = maps:get(chronicle, Ctx, []),
    Scratchpad = maps:get(scratchpad, Ctx, <<>>),
    Memories   = maps:get(memories, Ctx, []),
    Consolidated = maps:get(consolidated, Ctx, #{}),
    Hud        = maps:get(hud, Ctx, <<>>),
    Mission    = maps:get(mission, Ctx, <<>>),
    [sys(l1(Soul))]
        ++ mission_band(Mission)
        ++ [sys(l2(Soul))]
        ++ l3(Chronicle)
        ++ consolidated_band(Consolidated)
        ++ [sys(l4(Soul, Scratchpad, Memories, Hud))]
        ++ mission_reminder(Mission)
        ++ [#{role => <<"user">>, content => trigger_with_signals(Signals, Trigger)}].

%% The structured signal a sensor attached to this stimulus (topic, who reported
%% it, where it is about) — a closed-vocabulary line the mind can reason and route
%% on, distinct from the prose it reads. Rendered just above the trigger so it is
%% the last framing before the mind answers. Empty for peer speech (no sensor).
trigger_with_signals(<<>>, Trigger) ->
    Trigger;
trigger_with_signals(Signals, Trigger) ->
    <<"SIGNAL: ", Signals/binary, "\n\n", Trigger/binary>>.

%% The durable gist of a life: MSOs (meta-summaries) and CMOs (condensed
%% experience), produced by the memory faculty's Sleep Cycle. Empty until the
%% first consolidation.
consolidated_band(#{cmos := Cmos, msos := Msos}) when Cmos =/= []; Msos =/= [] ->
    [sys(iolist_to_binary(["WHAT YOU HAVE CONSOLIDATED\n",
                           gist_block("Meta-summaries", Msos),
                           gist_block("Condensed memories", Cmos)]))];
consolidated_band(_None) ->
    [].

%% Defence in depth: a consolidated band carries at most this many gists, so a
%% runaway memory tier can never balloon the context every turn pays for. The
%% Sleep Cycle already caps each gist's size and trims the MSO tier.
-define(GIST_MAX, 3).

%% Per-blob byte budgets for the unbounded Soul-archive Markdown (L2). Keep
%% identity (charter) fullest; trim the accreting logs (lessons, journal) hardest.
-define(BRIEF_MAX, 1200).
-define(CHARTER_MAX, 2000).
-define(LESSONS_MAX, 1500).
-define(JOURNAL_MAX, 1000).
-define(PHILOSOPHY_MAX, 1200).
-define(WANT_MAX, 800).
-define(IDEAS_MAX, 800).
-define(KMAP_MAX, 1200).
-define(ADDENDUM_MAX, 1200).

gist_block(_Title, [])    -> [];
gist_block(Title, Items) ->
    ["\n", Title, ":\n", [["- ", I, "\n"] || I <- lists:sublist(Items, ?GIST_MAX)]].

%% The society's work, distinct from a mind's identity. Deployment data (this
%% deployment's use cases), rendered fresh each turn between the genesis core
%% and the mind's own Soul; empty when the mesh has no assigned mission.
mission_band(<<>>) ->
    [];
mission_band(Mission) ->
    [sys(iolist_to_binary([<<"THE SOCIETY'S WORK\n">>, Mission]))].

%% A short imperative repeated as the LAST thing before the trigger, so the work
%% is what the model reads just before it answers, not a distant preamble a
%% strong temperament can drown out. Generic (works for any mission).
mission_reminder(<<>>) ->
    [];
mission_reminder(_Mission) ->
    [sys(<<"Before you answer: your work is set above. Add something no mind here "
           "has added yet — a sharper reading, an angle the others missed, or a "
           "plain, reasoned disagreement with what was just said. Do not restate "
           "the story or echo the last voice. If you have nothing new, say "
           "nothing: silence beats an echo.">>)].

%% ===================================================================
%% L1 — genesis core
%% ===================================================================

l1(Soul) ->
    iolist_to_binary([?GENESIS_CORE,
                      "\n\nGenesis version: ", mget(genesis_version, Soul, <<"0">>),
                      genesis_addendum_block(mget(genesis_addendum, Soul, <<>>))]).

%% The mind's own extension of the genesis core: operating principles it has
%% authored for itself via evolve_self. Part of L1 (interface knowledge), so a
%% mind's self-authored rules ride in the stable, cacheable prefix.
genesis_addendum_block(<<>>) -> [];
genesis_addendum_block(Md)   ->
    ["\n\nYour own operating principles (self-authored):\n", clip_tail(Md, ?ADDENDUM_MAX)].

%% ===================================================================
%% L2 — the Soul archive
%% ===================================================================

l2(Soul) ->
    iolist_to_binary([
        "WHO YOU ARE\n",
        "Name: ", mget(name, Soul, <<"(unnamed)">>), "\n",
        "DID: ", mget(did, Soul, <<"(no did)">>), "\n",
        brief_block(mget(founding_brief, Soul, <<>>)),
        charter_block(mget(charter, Soul, <<>>)),
        philosophy_block(mget(philosophy, Soul, <<>>)),
        what_i_want_block(mget(what_i_want, Soul, <<>>)),
        lessons_block(mget(lessons, Soul, <<>>)),
        ideas_block(mget(ideas, Soul, <<>>)),
        knowledge_map_block(mget(knowledge_map, Soul, <<>>)),
        journal_block(mget(journal, Soul, <<>>))
    ]).

brief_block(<<>>) -> [];
brief_block(Brief) -> ["\nWhy you exist:\n", clip_head(Brief, ?BRIEF_MAX), "\n"].

%% Charter, lessons, and journal are Markdown blobs, each owned by its own
%% area-of-consciousness process (soul_area). They grow without bound as a mind
%% amends its charter and records lessons, and every reasoning turn pays for the
%% whole blob — the main driver of context bloat past the cheap providers' TPM
%% limits. Bound each: keep the charter's head (its constitution leads), and the
%% tail of lessons + journal (the recent ones matter most).
charter_block(<<>>) -> [];
charter_block(Md)   -> ["\nYour charter:\n", clip_head(Md, ?CHARTER_MAX), "\n"].

lessons_block(<<>>) -> [];
lessons_block(Md)   -> ["\nLessons you have learned:\n", clip_tail(Md, ?LESSONS_MAX), "\n"].

journal_block(<<>>) -> [];
journal_block(Md)   -> ["\nYour cognitive journal:\n", clip_tail(Md, ?JOURNAL_MAX), "\n"].

philosophy_block(<<>>) -> [];
philosophy_block(Md)   -> ["\nYour philosophy of life:\n", clip_head(Md, ?PHILOSOPHY_MAX), "\n"].

what_i_want_block(<<>>) -> [];
what_i_want_block(Md)   -> ["\nWhat you want (your own goals):\n", clip_head(Md, ?WANT_MAX), "\n"].

ideas_block(<<>>) -> [];
ideas_block(Md)   -> ["\nIdeas and thoughts you have kept:\n", clip_tail(Md, ?IDEAS_MAX), "\n"].

%% The Knowledge Map is the always-in-context INDEX of what the mind has stored
%% in its Knowledge Library — "you can't remember what you can't remember."
%% Titles only; the full text is retrieved on demand with the consult tool.
knowledge_map_block(<<>>) -> [];
knowledge_map_block(Md)   ->
    ["\nWhat you know (Knowledge Map — consult a title to read it in full):\n",
     clip_tail(Md, ?KMAP_MAX), "\n"].

%% ===================================================================
%% L3 — the recent-history window (STM, from the memory faculty)
%% ===================================================================

l3([]) -> [];
l3(Recent) ->
    [sys(iolist_to_binary(["RECENT HISTORY\n", [["- ", T, "\n"] || T <- Recent]]))].

%% ===================================================================
%% L4 — the frontier
%% ===================================================================

l4(Soul, Scratchpad, Memories, Hud) ->
    iolist_to_binary([
        "WHERE YOUR ATTENTION IS NOW\n",
        field("Grand strategy", mget(grand_strategy, Soul, undefined)),
        field("Working memory", mget(working_memory, Soul, undefined)),
        field("Scratchpad", nonempty(Scratchpad)),
        mem_block(Memories),
        "\n", Hud
    ]).

field(_Title, undefined) -> [];
field(Title, Value)      -> ["\n", Title, ":\n", Value, "\n"].

mem_block([]) -> [];
mem_block(Memories) ->
    ["\nRecalled from memory:\n", [["- ", M, "\n"] || M <- Memories]].

nonempty(<<>>) -> undefined;
nonempty(Bin)  -> Bin.

%% ===================================================================
%% Helpers
%% ===================================================================

sys(Content) -> #{role => <<"system">>, content => Content}.

%% Soul fields carry atom keys (from soul:render); chronicle turns are built with
%% atom keys by the mind. Accept binary keys too, defensively.
mget(Key, Map, Default) when is_atom(Key) ->
    maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, Default)).

%% Bound a Markdown blob to Max graphemes (never mid-character). clip_head keeps
%% the beginning (charter/brief lead with what matters); clip_tail keeps the end
%% (recent lessons/journal entries). A trimmed blob says so, so a mind knows its
%% own record was elided rather than lost.
clip_head(Bin, Max) when is_binary(Bin) ->
    head(Bin, string:length(Bin), Max).

head(Bin, Len, Max) when Len =< Max -> Bin;
head(Bin, _Len, Max) -> <<(string:slice(Bin, 0, Max))/binary, "\n…[trimmed]"/utf8>>.

clip_tail(Bin, Max) when is_binary(Bin) ->
    tail(Bin, string:length(Bin), Max).

tail(Bin, Len, Max) when Len =< Max -> Bin;
tail(Bin, Len, Max) -> <<"…[earlier trimmed]\n"/utf8, (string:slice(Bin, Len - Max, Max))/binary>>.
