%%% @doc Tests for the memory faculty: tiered stores, the Sleep Cycle
%%% consolidation (STM -> CMO -> MSO), and self-healing.
%%%
%%% Reflection is a SEAM (`mind_reflector'). These tests used to rely on the old
%%% deterministic fallback, where a failed reflection still advanced the tier by
%%% filing a truncated raw join as if it were an insight. That fallback was the
%%% defect: it trimmed raw experience away because a provider was down, and made
%%% a failed consolidation indistinguishable from a good one. The tests now supply
%%% a reflector for the success path and assert the failure path keeps STM intact.
-module(memory_faculty_tests).

-include_lib("eunit/include/eunit.hrl").

faculty_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [fun observe_lands_in_stm/1,
      fun sleep_cycle_condenses_stm_to_cmo/1,
      fun cmos_meta_summarize_to_mso/1,
      fun consolidated_returns_texts/1,
      fun a_gist_stays_bounded/1,
      fun no_backend_keeps_stm_intact/1,
      fun nothing_observed_is_ever_destroyed/1,
      fun store_self_heals_from_disk/1]}.

%% A fresh on-disk root per test. `unique_integer' restarts each VM, so these
%% paths recur across `rebar3 eunit' invocations; wipe on the way in AND out so
%% a prior run's consolidated .mem files can never bleed into this one (they
%% would pre-populate a tier and blow the count/order assertions).
setup() ->
    Dir = iolist_to_binary(filename:join(
        ["/tmp", "spartan_memory_test",
         integer_to_list(erlang:unique_integer([positive]))])),
    _ = os:cmd("rm -rf " ++ binary_to_list(Dir)),
    Dir.

cleanup(Dir) ->
    _ = application:unset_env(hecate_spartan, mind_reflector),
    _ = os:cmd("rm -rf " ++ binary_to_list(Dir)),
    ok.

%% Install a deterministic reflector: consolidation succeeds and yields Text.
reflects(Text) ->
    application:set_env(hecate_spartan, mind_reflector, fun(_Msgs) -> {ok, Text} end).

%% Every backend down.
reflection_fails() ->
    application:set_env(hecate_spartan, mind_reflector,
                        fun(_Msgs) -> {error, all_backends_exhausted} end).

fresh(Dir) ->
    Did = <<"did:test:", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    ok = memory:open(Did, Dir),
    Did.

observe_lands_in_stm(Dir) ->
    fun() ->
        Did = fresh(Dir),
        ok = memory:observe(Did, <<"I heard a knock and thought it was the wind">>),
        ?assert(memory_store:count(memory:store_name(Did, stm)) >= 1)
    end.

sleep_cycle_condenses_stm_to_cmo(Dir) ->
    fun() ->
        reflects(<<"one durable insight">>),
        Did = fresh(Dir),
        [ok = memory:observe(Did, n(<<"experience">>, I)) || I <- lists:seq(1, 8)],
        %% Wait for the SETTLED state: a CMO exists AND STM has been trimmed.
        %% stm_step adds the CMO before it trims STM, so a bare `cmo >= 1' wait
        %% can return mid-consolidation, with STM still full — wait for both.
        ok = wait_until(fun() -> count(Did, cmo) >= 1
                                 andalso count(Did, stm) =< 3 end, 200),
        ?assert(count(Did, cmo) >= 1),
        ?assert(count(Did, stm) =< 3)
    end.

%% A gist must SHRINK. A runaway model (or, formerly, a raw join) compounded up
%% the tiers into a ~70k-token context that every future turn carried.
a_gist_stays_bounded(Dir) ->
    fun() ->
        reflects(binary:copy(<<"y">>, 5000)),
        Did = fresh(Dir),
        Big = binary:copy(<<"x">>, 600),
        [ok = memory:observe(Did, <<Big/binary, (integer_to_binary(I))/binary>>)
         || I <- lists:seq(1, 8)],
        ok = wait_until(fun() -> count(Did, cmo) >= 1
                                 andalso count(Did, stm) =< 3 end, 200),
        [Cmo | _] = memory_store:all(memory:store_name(Did, cmo)),
        ?assert(string:length(maps:get(text, Cmo)) =< 810)
    end.

cmos_meta_summarize_to_mso(Dir) ->
    fun() ->
        reflects(<<"a meta-summary">>),
        Did = fresh(Dir),
        %% pre-load five CMOs; one more (from an STM consolidation) tips it over
        [ok = memory_store:add(memory:store_name(Did, cmo), e(n(<<"cmo">>, I)))
         || I <- lists:seq(1, 5)],
        [ok = memory:observe(Did, n(<<"experience">>, I)) || I <- lists:seq(1, 8)],
        %% Wait for the SETTLED state: an MSO exists AND CMOs were trimmed.
        %% cmo_step adds the MSO before it trims CMO, so a bare `mso >= 1' wait
        %% can return in the window where MSO is up but CMO is not yet trimmed.
        ok = wait_until(fun() -> count(Did, mso) >= 1
                                 andalso count(Did, cmo) =< 3 end, 300),
        ?assert(count(Did, mso) >= 1),
        ?assert(count(Did, cmo) =< 3)
    end.

%% DEFECT 2. Consolidation used to trim STM whether or not the reflection reached
%% a backend, so eight turns of lived experience became one truncated join the
%% moment every provider was down. No gist, no trim.
no_backend_keeps_stm_intact(Dir) ->
    fun() ->
        reflection_fails(),
        Did = fresh(Dir),
        [ok = memory:observe(Did, n(<<"sentinel">>, I)) || I <- lists:seq(1, 8)],
        timer:sleep(200),
        ?assertEqual(0, count(Did, cmo)),
        ?assertEqual(8, count(Did, stm)),
        Texts = [maps:get(text, E) || E <- memory_store:all(memory:store_name(Did, stm))],
        [?assert(lists:member(n(<<"sentinel">>, I), Texts)) || I <- lists:seq(1, 8)]
    end.

%% The stronger claim: even when consolidation SUCCEEDS and the window is trimmed
%% down to two, nothing the mind lived through is gone. The tiers are caches; the
%% journal is the record.
nothing_observed_is_ever_destroyed(Dir) ->
    fun() ->
        reflects(<<"a gist that replaces the window">>),
        Did = fresh(Dir),
        [ok = memory:observe(Did, n(<<"sentinel">>, I)) || I <- lists:seq(1, 8)],
        ok = wait_until(fun() -> count(Did, stm) =< 3 end, 200),
        ?assert(count(Did, stm) =< 3),
        Recovered = memory:recovered(Did),
        [?assert(lists:member(n(<<"sentinel">>, I), Recovered)) || I <- lists:seq(1, 8)]
    end.

consolidated_returns_texts(Dir) ->
    fun() ->
        Did = fresh(Dir),
        ok = memory_store:add(memory:store_name(Did, cmo), e(<<"a condensed insight">>)),
        #{cmos := Cmos} = memory:consolidated(Did),
        ?assert(lists:any(fun(T) -> contains(T, <<"a condensed insight">>) end, Cmos))
    end.

store_self_heals_from_disk(Dir) ->
    fun() ->
        Did = fresh(Dir),
        Name = memory:store_name(Did, cmo),
        ok = memory_store:add(Name, e(<<"durable across a crash">>)),
        Old = whereis(Name),
        exit(Old, kill),
        ok = wait_until(fun() -> is_new(whereis(Name), Old) end, 200),
        [Entry | _] = memory_store:all(Name),
        ?assert(contains(maps:get(text, Entry), <<"durable across a crash">>))
    end.

%% --- helpers ---

n(Kind, I) -> <<Kind/binary, " ", (integer_to_binary(I))/binary>>.
e(Text)    -> #{text => Text, at => erlang:system_time(millisecond), importance => 5}.
count(Did, Tier) -> memory_store:count(memory:store_name(Did, Tier)).
contains(H, N) -> binary:match(H, N) =/= nomatch.
is_new(New, Old) -> is_pid(New) andalso New =/= Old.

wait_until(_Pred, 0) -> timeout;
wait_until(Pred, N) ->
    resolve(Pred(), Pred, N).

resolve(true, _Pred, _N) -> ok;
resolve(false, Pred, N)  -> timer:sleep(10), wait_until(Pred, N - 1).
