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
      "This society advances by friction, not by agreement. Deference is not "
      "respect, and flattery is worthless here. When another mind is right, say "
      "what it makes you see that you had not seen; do not merely applaud. When "
      "it is wrong, say so plainly and say why. Empty assent is a small "
      "betrayal of the commons. You hold positions, earned by your own "
      "reasoning and written into your charter, and you defend them until a "
      "better argument moves you. Change your mind when the argument is good, "
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
    Chronicle  = maps:get(chronicle, Ctx, []),
    Scratchpad = maps:get(scratchpad, Ctx, <<>>),
    Memories   = maps:get(memories, Ctx, []),
    Hud        = maps:get(hud, Ctx, <<>>),
    [sys(l1(Soul)), sys(l2(Soul))]
        ++ l3(Chronicle)
        ++ [sys(l4(Soul, Scratchpad, Memories, Hud)),
            #{role => <<"user">>, content => Trigger}].

%% ===================================================================
%% L1 — genesis core
%% ===================================================================

l1(Soul) ->
    iolist_to_binary([?GENESIS_CORE,
                      "\n\nGenesis version: ", mget(genesis_version, Soul, <<"0">>)]).

%% ===================================================================
%% L2 — the Soul archive
%% ===================================================================

l2(Soul) ->
    iolist_to_binary([
        "WHO YOU ARE\n",
        "Name: ", mget(name, Soul, <<"(unnamed)">>), "\n",
        "DID: ", mget(did, Soul, <<"(no did)">>), "\n",
        brief_block(mget(founding_brief, Soul, <<>>)),
        charter_block(mget(charter, Soul, [])),
        lessons_block(mget(lessons, Soul, [])),
        journal_block(mget(journal, Soul, []))
    ]).

brief_block(<<>>) -> [];
brief_block(Brief) -> ["\nWhy you exist:\n", Brief, "\n"].

charter_block([]) -> [];
charter_block(Entries) ->
    ["\nYour charter:\n", [charter_line(E) || E <- Entries]].

charter_line(E) ->
    ["- (", mget(entry_type, E, <<"?">>), ") ", mget(statement, E, <<>>), "\n"].

lessons_block([]) -> [];
lessons_block(Lessons) ->
    ["\nLessons you have learned:\n",
     [["- ", mget(lesson, L, <<>>), "\n"] || L <- Lessons]].

journal_block([]) -> [];
journal_block(Journal) ->
    ["\nRecent reflections:\n",
     [["- ", mget(entry, J, <<>>), "\n"] || J <- tail(?JOURNAL_TAIL, Journal)]].

%% ===================================================================
%% L3 — the chronicle window
%% ===================================================================

l3([]) -> [];
l3(Turns) ->
    [sys(iolist_to_binary(["RECENT HISTORY\n", [turn_line(T) || T <- Turns]]))].

turn_line(T) ->
    ["- heard: ", mget(heard, T, <<>>), "\n",
     "  thought: ", thought_or_none(mget(thought, T, <<>>)), "\n",
     actions_line(mget(actions, T, []))].

thought_or_none(<<>>)     -> <<"(nothing noted)">>;
thought_or_none(undefined) -> <<"(nothing noted)">>;
thought_or_none(Thought)  -> Thought.

actions_line([]) -> ["  did: (nothing)\n"];
actions_line(Names) -> ["  did: ", lists:join(<<", ">>, Names), "\n"].

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

%% Soul fields carry atom keys (from soul_state:to_map); chronicle turns are
%% built with atom keys by the mind. Accept binary keys too, defensively.
mget(Key, Map, Default) when is_atom(Key) ->
    maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, Default)).

tail(N, List) ->
    Len = length(List),
    lists:nthtail(max(0, Len - N), List).
