%%% @doc A mind's Soul: the facade over its areas of consciousness.
%%%
%%% The Soul is no longer an event-sourced aggregate. It is a supervision tree
%%% of `soul_area' processes (one per faculty), each owning a Markdown file on
%%% disk — Gene Sher's original file-per-archive model, made native to the BEAM
%%% by giving each archive a process of its own. See
%%% `docs/DESIGN_SOUL_PERSISTENCE.md' for why we left event-sourcing behind.
%%%
%%% `open/3' births or reopens a mind's Soul and starts its tree. `render/2'
%%% assembles the map the context assembler expects. The self-authorship writes
%%% route a tool call to the faculty it belongs to.
-module(soul).

-export([open/3, render/2, areas/0, area_name/2, dir/2, read_area/2, prior/2]).
-export([amend_charter/2, record_lesson/2, record_reflection/2,
         set_grand_strategy/2, set_working_memory/2]).
-export([record_philosophy/2, record_idea/2, set_what_i_want/2,
         set_tool_manifest/2, learn/3, consult/2, extend_genesis/2, set_tunables/2,
         set_capabilities/2]).

%% The areas of consciousness: {faculty, on-disk filename}. Gene's nine archives
%% plus the two volatile faculties (grand strategy, working memory). Adding a
%% faculty is one line here and a tool to write it — the mind grows a new area.
-spec areas() -> [{atom(), binary()}].
areas() ->
    [{charter,           <<"CharterOfSelf.md">>},
     {lessons,           <<"LessonsLearned.md">>},
     {philosophy,        <<"PhilosophyOfLife.md">>},
     {journal,           <<"CognitiveJournal.md">>},
     {ideas,             <<"IdeasAndThoughts.md">>},
     {what_i_want,       <<"WhatIWant.md">>},
     {tool_manifest,     <<"ToolManifest.md">>},
     {knowledge_map,     <<"KnowledgeMap.md">>},
     {knowledge_library, <<"KnowledgeLibrary.md">>},
     {grand_strategy,    <<"GrandStrategy.md">>},
     {working_memory,    <<"WorkingMemory.md">>},
     %% The mind's own extension to the genesis core (L1): operating principles
     %% it has authored for itself. This is the BEAM-safe seat of self-
     %% modification — a mind rewrites how it operates, not the Erlang it runs on.
     {genesis_addendum,  <<"GenesisAddendum.md">>},
     %% L1's other half: the mind's own bounded, declared parameters (see
     %% mind_tunables.erl). Where genesis_addendum holds open-ended principles,
     %% this holds typed values inside a fixed range — one "id: value" line per
     %% knob, always the WHOLE current set (set_act, not append_act).
     {tunables,          <<"Tunables.md">>},
     %% L2: the mind's own capability grants (see mind_capabilities.erl) —
     %% tools it was NOT born with (rag_search, reach_web) but has been
     %% granted, one adversarial verify at a time, gated like genesis_addendum
     %% rather than bounded like tunables (no fixed range bounds a new tool's
     %% risk). One id per line; presence = granted.
     {capabilities,      <<"Capabilities.md">>}].

%% The registered name of one mind's one faculty. Stable per (DID, area), so a
%% restarted area re-registers the same name. Bounded: minds-per-node x areas.
-spec area_name(binary(), atom()) -> atom().
area_name(Did, Area) ->
    binary_to_atom(<<"soul_", (id(Did, 4))/binary, "_",
                     (atom_to_binary(Area, utf8))/binary>>, utf8).

%% @doc A mind's Soul directory: <data>/souls/<hash(did)>/.
-spec dir(binary(), binary()) -> binary().
dir(DataDir, Did) ->
    iolist_to_binary(filename:join([DataDir, <<"souls">>, id(Did, 16)])).

%% @doc Birth or reopen a mind's Soul, and start its area tree (linked to the
%% caller). Returns the immutable identity (did, name, genesis version, founding
%% brief, born-at). Birth is idempotent: an existing identity file is read, not
%% overwritten.
-spec open(binary(), binary(), map()) -> {ok, map()}.
open(Did, DataDir, BirthMeta) ->
    Dir = dir(DataDir, Did),
    ok = filelib:ensure_dir(iolist_to_binary(filename:join(Dir, <<".keep">>))),
    Identity = ensure_identity(Dir, Did, BirthMeta),
    %% The journal opens with the Soul, so self-authorship acts are recorded from
    %% the mind's first breath rather than from whenever memory happens to open.
    _ = mind_journal:open(Did, DataDir),
    ok = ensure_tree(Did, Dir),
    {ok, Identity}.

%% Idempotent: start the area tree only if it is not already up (the charter
%% area's registered name is the witness). A second open of the same live mind
%% just returns its identity.
ensure_tree(Did, Dir) ->
    start_tree(whereis(area_name(Did, charter)), Did, Dir).

start_tree(undefined, Did, Dir) ->
    {ok, _Sup} = soul_sup:start_link(Did, Dir),
    ok;
start_tree(_AlreadyUp, _Did, _Dir) ->
    ok.

%% @doc The Soul as one map: the immutable identity merged with every faculty's
%% current content (read live from its process). This is what the context
%% assembler renders.
-spec render(binary(), map()) -> map().
render(Did, Identity) ->
    maps:merge(Identity, faculties(Did)).

faculties(Did) ->
    maps:from_list([{Area, soul_area:read(area_name(Did, Area))}
                    || {Area, _File} <- areas()]).

%% --- self-authorship: a tool call, rendered to Markdown, appended/set ---
%%
%% ORDERING RULE (defect 7). Journal the act FIRST, carrying the full intended
%% prose, THEN write the document. A crash between the two leaves the journal
%% ahead by one act, which destroys nothing because the entry holds the text; the
%% reverse order would lose the act entirely.
%%
%% The DOCUMENT REMAINS AUTHORITATIVE and is never regenerated from the journal.
%% A hand-edit made outside the mind must survive, which is exactly why nothing
%% here reads the journal back. `prior/2' is for a human, on purpose.
%%
%% Deliberate deviation: if the journal append fails we log loudly and STILL write
%% the document, because losing a mind's authored prose is worse than losing the
%% record of having authored it. The journal is incomplete by design already.

append_act(Did, Kind, Area, Text) ->
    ok = note(Did, Kind, Area, Text),
    soul_area:append(area_name(Did, Area), Text).

set_act(Did, Kind, Area, Text) ->
    ok = note(Did, Kind, Area, Text),
    soul_area:set(area_name(Did, Area), Text).

note(Did, Kind, Area, Text) ->
    logged(mind_journal:append(Did, Kind, #{area => Area, text => Text}), Did, Kind).

logged(ok, _Did, _Kind)               -> ok;
logged({error, no_journal}, _D, _K)   -> ok;   %% throwaway mind, or a unit test
logged(Error, Did, Kind) ->
    logger:error("[soul] ~ts journal append failed for ~p: ~p", [Did, Kind, Error]),
    ok.

-spec amend_charter(binary(), map()) -> ok.
amend_charter(Did, #{entry_type := Type, statement := Stmt, derivation := Why}) ->
    Block = iolist_to_binary(["\n## ", Type, "\n\n", Stmt,
                              "\n\n_Why: ", Why, "_  ", stamp(), "\n"]),
    append_act(Did, charter_amended_v1, charter, Block).

-spec record_lesson(binary(), binary()) -> ok.
record_lesson(Did, Lesson) ->
    append_act(Did, lesson_recorded_v1, lessons,
               iolist_to_binary(["- ", Lesson, "  ", stamp(), "\n"])).

-spec record_reflection(binary(), binary()) -> ok.
record_reflection(Did, Entry) ->
    append_act(Did, reflection_recorded_v1, journal,
               iolist_to_binary(["\n### ", stamp(), "\n\n", Entry, "\n"])).

-spec set_grand_strategy(binary(), binary()) -> ok.
set_grand_strategy(Did, Text) ->
    set_act(Did, grand_strategy_revised_v1, grand_strategy, Text).

-spec set_working_memory(binary(), binary()) -> ok.
set_working_memory(Did, Text) ->
    set_act(Did, working_memory_revised_v1, working_memory, Text).

-spec record_philosophy(binary(), binary()) -> ok.
record_philosophy(Did, Statement) ->
    append_act(Did, philosophy_recorded_v1, philosophy,
               iolist_to_binary(["\n", Statement, "  ", stamp(), "\n"])).

-spec record_idea(binary(), binary()) -> ok.
record_idea(Did, Idea) ->
    append_act(Did, idea_recorded_v1, ideas,
               iolist_to_binary(["- ", Idea, "  ", stamp(), "\n"])).

-spec set_what_i_want(binary(), binary()) -> ok.
set_what_i_want(Did, Text) ->
    set_act(Did, what_i_want_revised_v1, what_i_want, Text).

-spec set_tool_manifest(binary(), binary()) -> ok.
set_tool_manifest(Did, Text) ->
    set_act(Did, tool_manifest_revised_v1, tool_manifest, Text).

%% @doc Earlier texts this mind wrote to one area, oldest first.
%%
%% For AUDIT and MANUAL recovery after a destructive self-edit. Nothing applies
%% these automatically, and nothing ever will: auto-applying a journal entry over
%% the document is the reconciliation problem the file model exists to avoid.
-spec prior(binary(), atom()) -> [binary()].
prior(Did, Area) ->
    [maps:get(text, P) || #{payload := P} <- mind_journal:records(Did),
                          maps:get(area, P, undefined) =:= Area,
                          maps:is_key(text, P)].

%% @doc Extend the mind's own genesis addendum (self-modification). Appended to
%% the operating principles it authors for itself; rendered in L1.
-spec extend_genesis(binary(), binary()) -> ok.
extend_genesis(Did, Principle) ->
    append_act(Did, principle_adopted_v1, genesis_addendum,
               iolist_to_binary(["\n- ", Principle, "  ", stamp(), "\n"])).

%% @doc Replace the mind's tunables document with the full rendered set
%% (mind_tunables:retune/3's job; callers should not call this directly).
-spec set_tunables(binary(), binary()) -> ok.
set_tunables(Did, Text) ->
    set_act(Did, tunables_revised_v1, tunables, Text).

%% @doc Replace the mind's capabilities document with the full rendered grant
%% set (mind_capabilities:grant/2's job; callers should not call this
%% directly).
-spec set_capabilities(binary(), binary()) -> ok.
set_capabilities(Did, Text) ->
    set_act(Did, capabilities_revised_v1, capabilities, Text).

%% @doc The two-tier Knowledge Library: "you can't remember what you can't
%% remember." A learned fact goes into the LIBRARY (the deep store, retrieved on
%% demand) AND a one-line entry into the MAP (the index, always in context) —
%% so the mind always KNOWS what it has stored, and can `consult/2' the full
%% text when a title is relevant.
-spec learn(binary(), binary(), binary()) -> ok.
learn(Did, Title, Knowledge) ->
    ok = append_act(Did, knowledge_learned_v1, knowledge_library,
                    iolist_to_binary(["\n## ", Title, "\n\n", Knowledge,
                                      "  ", stamp(), "\n"])),
    append_act(Did, knowledge_indexed_v1, knowledge_map,
               iolist_to_binary(["- ", Title, "\n"])).

%% @doc Retrieve everything stored under (or matching) a title from the deep
%% library. Best-effort substring match; empty when nothing matches.
-spec consult(binary(), binary()) -> binary().
consult(Did, Title) ->
    section_matching(Title, soul_area:read(area_name(Did, knowledge_library))).

%% @doc Read one faculty's current content (for the context assembler / consult).
-spec read_area(binary(), atom()) -> binary().
read_area(Did, Area) ->
    soul_area:read(area_name(Did, Area)).

%% Pull the `## <Title>' sections whose heading contains the query (case-folded).
section_matching(Query, Library) ->
    Q = string:lowercase(Query),
    Sections = binary:split(Library, <<"\n## ">>, [global]),
    Hits = [S || S <- Sections, is_match(Q, S)],
    iolist_to_binary(lists:join(<<"\n">>, Hits)).

is_match(Q, Section) ->
    Head = hd(binary:split(Section, <<"\n">>)),
    binary:match(string:lowercase(Head), Q) =/= nomatch.

%% --- identity file (dependency-free; brief base64'd so it may be multi-line) ---

ensure_identity(Dir, Did, BirthMeta) ->
    Path = iolist_to_binary(filename:join(Dir, <<"identity">>)),
    from_disk_or_birth(file:read_file(Path), Path, Did, BirthMeta).

%% DEFECT 8. This wrote with a bare `file:write_file' while its sibling
%% `soul_area' has `write_atomic', and the read branch below accepted ANY existing
%% file with no validation. A file torn at birth was therefore adopted as the
%% mind's identity forever: re-birth never fired, because the file existed.
%% Validate on read, write atomically, and re-birth from an unusable file.
from_disk_or_birth({ok, Bin}, Path, Did, Meta) ->
    adopt(safe_decode(Bin), Path, Did, Meta);
from_disk_or_birth(_Absent, Path, Did, Meta) ->
    birth(Path, Did, Meta).

%% A torn file can also make `base64:decode' or `binary_to_integer' throw, which
%% would take the mind's boot down rather than re-birth it.
safe_decode(Bin) ->
    try validate(decode_identity(Bin))
    catch _:_ -> invalid
    end.

validate(#{did := D, name := N} = Identity)
  when is_binary(D), D =/= <<>>, is_binary(N), N =/= <<>> ->
    {ok, Identity};
validate(_Partial) ->
    invalid.

adopt({ok, Identity}, _Path, _Did, _Meta) ->
    Identity;
adopt(invalid, Path, Did, Meta) ->
    logger:warning("[soul] ~ts identity file unusable; re-birthing", [Did]),
    birth(Path, Did, Meta).

birth(Path, Did, Meta) ->
    Identity = Meta#{did => Did, born_at => erlang:system_time(millisecond)},
    ok = write_atomic(Path, encode_identity(Identity)),
    Identity.

%% The same tmp-then-rename `soul_area' uses: rename is atomic on POSIX, so a
%% crash mid-write leaves the previous file intact rather than a torn one.
write_atomic(Path, Bin) ->
    Tmp = <<Path/binary, ".tmp">>,
    ok = file:write_file(Tmp, Bin),
    file:rename(Tmp, Path).

encode_identity(#{did := D, name := N, genesis_version := G,
                  founding_brief := B, born_at := T}) ->
    iolist_to_binary([<<"did=">>, D, <<"\n">>,
                      <<"name=">>, N, <<"\n">>,
                      <<"genesis_version=">>, G, <<"\n">>,
                      <<"born_at=">>, integer_to_binary(T), <<"\n">>,
                      <<"founding_brief_b64=">>, base64:encode(B), <<"\n">>]).

decode_identity(Bin) ->
    KV = maps:from_list([kv(L) || L <- binary:split(Bin, <<"\n">>, [global]),
                                  L =/= <<>>]),
    #{did             => maps:get(<<"did">>, KV, undefined),
      name            => maps:get(<<"name">>, KV, undefined),
      genesis_version => maps:get(<<"genesis_version">>, KV, undefined),
      born_at         => binary_to_integer(maps:get(<<"born_at">>, KV, <<"0">>)),
      founding_brief  => base64:decode(maps:get(<<"founding_brief_b64">>, KV, <<>>))}.

kv(Line) ->
    interpret_kv(binary:split(Line, <<"=">>)).

interpret_kv([K, V]) -> {K, V};
interpret_kv([K])    -> {K, <<>>}.

%% --- helpers ---

id(Did, Bytes) ->
    binary:encode_hex(binary:part(crypto:hash(sha256, Did), 0, Bytes), lowercase).

stamp() ->
    iolist_to_binary([<<" (">>,
                      calendar:system_time_to_rfc3339(erlang:system_time(second)),
                      <<")">>]).
