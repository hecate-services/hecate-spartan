%%% @doc A mind's own capability grants: L2 self-modification.
%%%
%%% L1 (mind_tunables.erl) retunes a bounded, declared VALUE; its own fixed
%%% range is the whole safety mechanism, so no verifier is needed. A
%%% capability grant is a bigger act: it puts a NEW TOOL in the mind's own
%%% hands (reach into the RAG mesh, reach onto the open web) — no range
%%% bounds that, so a grant passes through the same adversarial gate as
%%% evolve_self (mind_verifier.erl), weighed against the mind's own charter.
%%%
%%% Persisted the same way as every other act of self-authorship (soul.erl):
%%% the journal records the act first, then the Capabilities.md document is
%%% written — the WHOLE current grant set, one id per line (presence in the
%%% document = granted).
-module(mind_capabilities).

-export([schema/0, granted/1, has/2, grant/2]).

-type id() :: rag_search | rag_contribute | reach_web
            | graph_learn | graph_ask_entity | graph_ask_links.
-export_type([id/0]).

%% @doc The declared, grantable capabilities a mind may ask for. Adding one
%% here, a tool for it in mind_tools.erl, and a guarded dispatch clause is the
%% whole surface of a new capability.
-spec schema() -> [map()].
schema() ->
    [#{id => rag_search, tool => <<"rag_search">>,
       description => <<"Search the federated RAG mesh (macula_rag) for "
                        "passages relevant to a query, across every "
                        "advertised corpus in the realm, not only "
                        "hecate-rag's.">>},
     %% Granted separately from rag_search: reading the shared corpus and
     %% writing into it (visible to every other mind that searches it after)
     %% are different risk profiles — a mind can hold one without the other.
     #{id => rag_contribute, tool => <<"rag_contribute">>,
       description => <<"Write a finding into the shared RAG corpus so other "
                        "minds can discover it later via rag_search — the "
                        "society's compounding, shared memory, distinct from "
                        "a mind's own private Knowledge Library (learn).">>},
     #{id => reach_web, tool => <<"reach_web">>,
       description => <<"Fetch a single web page by URL and read its text.">>},
     %% Attribution note, honest about a real limit: a write here is made
     %% through hecate-spartan's own mesh connection, not a connection of
     %% the mind's own -- hecate-graph's provenance records the wire-
     %% authenticated caller, which is this spartan instance, not the
     %% individual mind. Granted per-mind for the mind's own sense of
     %% "have I told the graph this", not for individual credit there yet.
     #{id => graph_learn, tool => <<"graph_learn">>,
       description => <<"Teach the shared knowledge graph (hecate-graph) a "
                        "relationship: subject, predicate, object. Other "
                        "minds' graph_ask_* calls can find it after.">>},
     #{id => graph_ask_entity, tool => <<"graph_ask_entity">>,
       description => <<"Ask the shared knowledge graph what it knows about "
                        "one thing, in prose.">>},
     #{id => graph_ask_links, tool => <<"graph_ask_links">>,
       description => <<"Ask the shared knowledge graph how one thing "
                        "relates to others, in prose — optionally filtered "
                        "by relationship, direction, or hop depth.">>}].

%% @doc This mind's currently granted capabilities.
-spec granted(binary()) -> [id()].
granted(Did) ->
    parse(soul:read_area(Did, capabilities)).

-spec has(binary(), id()) -> boolean().
has(Did, Id) ->
    lists:member(Id, granted(Did)).

%% @doc Propose granting this mind one declared capability. Gated by the
%% adversarial verifier weighed against the mind's own charter. Idempotent:
%% granting an already-granted capability is a no-op success, no second
%% verify call spent.
-spec grant(binary(), id()) -> {ok, granted} | {error, term()}.
grant(Did, Id) ->
    known(find(Id, schema()), Did, Id).

find(Id, Schema) -> one([S || #{id := I} = S <- Schema, I =:= Id]).
one([S]) -> S;
one([])  -> undefined.

known(undefined, _Did, Id) ->
    {error, {unknown_capability, Id}};
known(Spec, Did, Id) ->
    already_or_verify(lists:member(Id, granted(Did)), Spec, Did, Id).

already_or_verify(true, _Spec, _Did, _Id) ->
    {ok, granted};
already_or_verify(false, Spec, Did, Id) ->
    Charter = soul:read_area(Did, charter),
    adopt(mind_verifier:verify(proposal(Spec), Charter), Did, Id).

proposal(#{tool := Tool, description := Desc}) ->
    <<"Proposed new capability for yourself: the ", Tool/binary, " tool. ", Desc/binary>>.

adopt(approved, Did, Id) ->
    ok = soul:set_capabilities(Did, render([Id | granted(Did)])),
    {ok, granted};
adopt(rejected, _Did, _Id) ->
    {error, rejected_by_verifier}.

%% --- rendering / parsing (Capabilities.md: one granted id per line) ---

render(Ids) ->
    iolist_to_binary([[atom_to_binary(Id, utf8), <<"\n">>] || Id <- lists:usort(Ids)]).

parse(Text) ->
    lists:filtermap(fun parse_line/1, binary:split(Text, <<"\n">>, [global])).

parse_line(Line) ->
    known_id(existing_id(Line)).

%% `binary_to_existing_atom' rather than `binary_to_atom': Capabilities.md is
%% single-writer (this module) but, like every Soul area, a hand-edit must
%% survive without crashing the mind — never mint a new atom from file
%% content, only recognize the ids this module already declared.
existing_id(K) ->
    try binary_to_existing_atom(K, utf8) catch _:_ -> undefined end.

known_id(undefined) -> false;
known_id(Id)         -> present(find(Id, schema()), Id).

present(undefined, _Id) -> false;
present(_Spec, Id)      -> {true, Id}.
