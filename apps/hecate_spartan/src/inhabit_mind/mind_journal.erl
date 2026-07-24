%%% @doc A mind's journal: the append-only record of what it DID.
%%%
%%% `docs/DESIGN_SOUL_PERSISTENCE.md' recommended exactly this and only half of it
%%% shipped. Its words: "causal history / chronicle (turns, self-authorship acts):
%%% an append-only log. Append-only is a genuine fit — but that is a LOG, not
%%% event-sourcing-with-aggregates: no folding, no expected-version, no
%%% replay-to-state." Gene Sher has both halves (editable Markdown archives plus
%%% `session_raw_entry_accumulator.jsonl'); this port kept the archives and
%%% dropped the accumulator, which is where three defects came from.
%%%
%%% WHAT THIS IS NOT. The journal is not a second copy of the Soul, and the Soul
%%% is not derived from it. The document is state; the journal is a record of
%%% acts. The DOCUMENT ALWAYS WINS, unconditionally. Two rules follow, and they
%%% are requirements, not preferences:
%%%
%%%   1. A journal entry that is ahead of the document is NEVER auto-applied at
%%%      boot. Recovery is manual and assisted. Auto-applying reintroduces the
%%%      reconciliation problem the file model was chosen to avoid.
%%%   2. No drift detector. Diffing a document against the journal is undecidable
%%%      by construction: a hand-edit made outside the mind (which MUST survive)
%%%      and a crash-window gap are indistinguishable. Any such detector either
%%%      reverts real edits or cries wolf.
%%%
%%% The journal is therefore incomplete by design (hand-edits bypass it) and may
%%% be ahead by one act after a crash. It is an archive of what the mind did, not
%%% a history of what its files contain.
%%%
%%% Mechanics: one file per mind, records appended at the end and fsynced, never
%%% rewritten. Appends are SYNCHRONOUS on purpose — the ordering rule (journal
%%% first carrying the full prose, then the document write) is only enforceable if
%%% the caller can wait for the append. A crash mid-append leaves a short final
%%% frame, which the reader stops at; everything before it is intact.
-module(mind_journal).
-behaviour(gen_server).

-export([open/2, append/3, records/1, records/2, texts/2, name/1, path/2, from_disk/1]).
-export([start_link/1, init/1, handle_call/3, handle_cast/2, terminate/2]).

-type record() :: #{kind := atom(), at := integer(), payload := map()}.
-export_type([record/0]).

-define(APPEND_TIMEOUT_MS, 5000).

%% @doc The registered name of one mind's journal.
-spec name(binary()) -> atom().
name(Did) ->
    binary_to_atom(<<"journal_", (id(Did))/binary>>, utf8).

%% @doc <data>/journal/<hash(did)>.journal
-spec path(binary(), binary()) -> binary().
path(DataDir, Did) ->
    iolist_to_binary(filename:join([DataDir, <<"journal">>, <<(id(Did))/binary, ".journal">>])).

%% @doc Start (idempotently) a mind's journal. Linked to the caller, like the
%% other faculties.
-spec open(binary(), binary()) -> ok | {error, term()}.
open(Did, DataDir) ->
    Path = path(DataDir, Did),
    ok = filelib:ensure_dir(Path),
    ensure(whereis(name(Did)), Did, Path).

ensure(undefined, Did, Path) -> started(start_link(#{did => Did, path => Path}));
ensure(_AlreadyUp, _Did, _Path) -> ok.

started({ok, _Pid}) -> ok;
started(Other)      -> {error, Other}.

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(#{did := Did} = Spec) ->
    gen_server:start_link({local, name(Did)}, ?MODULE, Spec, []).

%% @doc Record one act. Synchronous and fsynced: callers that follow the ordering
%% rule need to know the record is durable BEFORE they touch the document.
%% Returns `{error, no_journal}' when a mind is running without one (throwaway
%% minds, unit tests) so callers can degrade rather than crash.
-spec append(binary(), atom(), map()) -> ok | {error, term()}.
append(Did, Kind, Payload) ->
    send(whereis(name(Did)),
         #{kind => Kind, at => erlang:system_time(millisecond), payload => Payload}).

send(undefined, _Rec) -> {error, no_journal};
send(Pid, Rec)        -> catch gen_server:call(Pid, {append, Rec}, ?APPEND_TIMEOUT_MS).

%% @doc Every record, oldest first.
-spec records(binary()) -> [record()].
records(Did) ->
    ask(whereis(name(Did))).

ask(undefined) -> [];
ask(Pid)       -> gen_server:call(Pid, records).

%% @doc Records of the given kinds, oldest first.
-spec records(binary(), [atom()]) -> [record()].
records(Did, Kinds) ->
    [R || #{kind := K} = R <- records(Did), lists:member(K, Kinds)].

%% @doc The `text' payload of every record of the given kinds, oldest first. This
%% is what makes destructive trim impossible: whatever a cache window drops is
%% still here.
-spec texts(binary(), [atom()]) -> [binary()].
texts(Did, Kinds) ->
    [T || #{payload := P} <- records(Did, Kinds),
          (T = maps:get(text, P, <<>>)) =/= <<>>].

%% @doc Read a journal straight off disk, without its process. For recovery and
%% for inspecting a mind that is not running.
-spec from_disk(binary()) -> [record()].
from_disk(Path) ->
    frames(read_all(Path), []).

%% --- gen_server ---

init(#{path := Path} = Spec) ->
    {ok, Fd} = file:open(Path, [append, raw, binary]),
    {ok, Spec#{fd => Fd}}.

handle_call({append, Rec}, _From, #{fd := Fd} = S) ->
    {reply, write(Fd, Rec), S};
handle_call(records, _From, #{path := Path} = S) ->
    {reply, from_disk(Path), S};
handle_call(_Other, _From, S) ->
    {reply, {error, unknown_request}, S}.

handle_cast(_Msg, S) ->
    {noreply, S}.

terminate(_Reason, #{fd := Fd}) ->
    _ = file:close(Fd),
    ok;
terminate(_Reason, _NoFd) ->
    ok.

%% --- framing ---

%% Length-prefixed frames, so a torn tail is detectable rather than poisoning the
%% decode of everything after it.
write(Fd, Rec) ->
    Bin = term_to_binary(Rec),
    durable(file:write(Fd, <<(byte_size(Bin)):32, Bin/binary>>), Fd).

%% fsync per record. `rename' is atomic for readers but not durable across power
%% loss, and this is the one place worth paying for durability.
durable(ok, Fd)     -> file:datasync(Fd);
durable(Error, _Fd) -> Error.

read_all(Path) -> interpret_read(file:read_file(Path)).

interpret_read({ok, Bin}) -> Bin;
interpret_read(_Absent)   -> <<>>.

%% A crash mid-append leaves a short final frame. Stop there: everything before it
%% is intact, and a partial record never happened as far as the mind is concerned.
frames(<<Size:32, Bin:Size/binary, Rest/binary>>, Acc) ->
    continue(safe_term(Bin), Rest, Acc);
frames(_TornTail, Acc) ->
    lists:reverse(Acc).

continue({ok, Rec}, Rest, Acc) -> frames(Rest, [Rec | Acc]);
continue(error, _Rest, Acc)    -> lists:reverse(Acc).

safe_term(Bin) ->
    try {ok, binary_to_term(Bin)}
    catch _:_ -> error
    end.

id(Did) ->
    binary:encode_hex(binary:part(crypto:hash(sha256, Did), 0, 8), lowercase).
