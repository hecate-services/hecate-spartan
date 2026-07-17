%%% @doc A mind's memory faculty: the facade over its tiered stores and its
%%% Sleep Cycle. See docs/DESIGN_MIND_FACULTIES.md.
%%%
%%% Tiers: STM (raw recent), CMO (condensed), MSO (meta-summaries). The mind
%%% `observe/2's each substantive turn into STM and nudges the Sleep Cycle, which
%%% consolidates upward when a tier fills. `consolidated/1' returns the condensed
%%% memory (CMOs + MSOs) for the mind's context: the durable gist of a life the
%%% raw window would otherwise forget.
%%%
%%% Long-term semantic recall stays in mind_memory (hecate-vector) for now; this
%%% faculty owns the consolidation hierarchy.
-module(memory).

-export([open/2, observe/2, consolidated/1, recent_stm/2, tiers/0, store_name/2, sleep_name/1]).

-spec tiers() -> [{atom(), binary()}].
tiers() ->
    [{stm, <<"ShortTermMemory.mem">>},
     {cmo, <<"CondensedMemory.mem">>},
     {mso, <<"MetaSummary.mem">>}].

-spec store_name(binary(), atom()) -> atom().
store_name(Did, Tier) ->
    binary_to_atom(<<"mem_", (id(Did))/binary, "_",
                     (atom_to_binary(Tier, utf8))/binary>>, utf8).

-spec sleep_name(binary()) -> atom().
sleep_name(Did) ->
    binary_to_atom(<<"sleep_", (id(Did))/binary>>, utf8).

%% @doc Start the memory faculty for a mind (idempotent, linked to the caller).
-spec open(binary(), binary()) -> ok | {error, term()}.
open(Did, DataDir) ->
    Dir = dir(DataDir, Did),
    ok = filelib:ensure_dir(iolist_to_binary(filename:join(Dir, <<".keep">>))),
    ensure_tree(whereis(sleep_name(Did)), Did, Dir).

ensure_tree(undefined, Did, Dir) ->
    started(catch memory_sup:start_link(Did, Dir));
ensure_tree(_AlreadyUp, _Did, _Dir) ->
    ok.

started({ok, _Sup}) -> ok;
started(Other)      -> {error, Other}.

%% @doc Record one lived experience into STM and ask the Sleep Cycle to consider
%% consolidating. Best-effort: a mind whose faculty is momentarily unavailable
%% simply does not record this one.
-spec observe(binary(), binary()) -> ok.
observe(Did, Text) when is_binary(Text), Text =/= <<>> ->
    _ = catch memory_store:add(store_name(Did, stm),
                               #{text => Text, at => erlang:system_time(millisecond),
                                 importance => 5}),
    _ = catch sleep_cycle:nudge(sleep_name(Did)),
    ok;
observe(_Did, _Empty) ->
    ok.

%% @doc The condensed memory for the mind's context: recent CMOs and all MSOs,
%% as their texts. Best-effort: no faculty yields nothing.
-spec consolidated(binary()) -> #{cmos := [binary()], msos := [binary()]}.
consolidated(Did) ->
    #{cmos => texts(catch memory_store:recent(store_name(Did, cmo), 4)),
      msos => texts(catch memory_store:all(store_name(Did, mso)))}.

%% @doc The most recent N raw experiences (STM), oldest first, as their texts.
%% This is the mind's recent-history window, replacing the event-sourced
%% chronicle: the same raw turns, now a faculty the Sleep Cycle also consolidates.
-spec recent_stm(binary(), non_neg_integer()) -> [binary()].
recent_stm(Did, N) ->
    texts(catch memory_store:recent(store_name(Did, stm), N)).

texts(Entries) when is_list(Entries) ->
    [maps:get(text, E, <<>>) || E <- Entries];
texts(_NotAList) ->
    [].

%% --- helpers ---

dir(DataDir, Did) ->
    iolist_to_binary(filename:join([DataDir, <<"memory">>, id(Did)])).

id(Did) ->
    binary:encode_hex(binary:part(crypto:hash(sha256, Did), 0, 4), lowercase).
