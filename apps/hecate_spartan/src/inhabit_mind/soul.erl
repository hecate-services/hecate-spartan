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

-export([open/3, render/2, areas/0, area_name/2, dir/2]).
-export([amend_charter/2, record_lesson/2, record_reflection/2,
         set_grand_strategy/2, set_working_memory/2]).

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
     {working_memory,    <<"WorkingMemory.md">>}].

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

-spec amend_charter(binary(), map()) -> ok.
amend_charter(Did, #{entry_type := Type, statement := Stmt, derivation := Why}) ->
    Block = iolist_to_binary(["\n## ", Type, "\n\n", Stmt,
                              "\n\n_Why: ", Why, "_  ", stamp(), "\n"]),
    soul_area:append(area_name(Did, charter), Block).

-spec record_lesson(binary(), binary()) -> ok.
record_lesson(Did, Lesson) ->
    soul_area:append(area_name(Did, lessons),
                     iolist_to_binary(["- ", Lesson, "  ", stamp(), "\n"])).

-spec record_reflection(binary(), binary()) -> ok.
record_reflection(Did, Entry) ->
    soul_area:append(area_name(Did, journal),
                     iolist_to_binary(["\n### ", stamp(), "\n\n", Entry, "\n"])).

-spec set_grand_strategy(binary(), binary()) -> ok.
set_grand_strategy(Did, Text) ->
    soul_area:set(area_name(Did, grand_strategy), Text).

-spec set_working_memory(binary(), binary()) -> ok.
set_working_memory(Did, Text) ->
    soul_area:set(area_name(Did, working_memory), Text).

%% --- identity file (dependency-free; brief base64'd so it may be multi-line) ---

ensure_identity(Dir, Did, BirthMeta) ->
    Path = iolist_to_binary(filename:join(Dir, <<"identity">>)),
    from_disk_or_birth(file:read_file(Path), Path, Did, BirthMeta).

from_disk_or_birth({ok, Bin}, _Path, _Did, _Meta) ->
    decode_identity(Bin);
from_disk_or_birth(_Absent, Path, Did, Meta) ->
    Identity = Meta#{did => Did, born_at => erlang:system_time(millisecond)},
    ok = file:write_file(Path, encode_identity(Identity)),
    Identity.

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
