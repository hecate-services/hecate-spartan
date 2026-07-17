%%% @doc Tests for the memory faculty: tiered stores, the Sleep Cycle
%%% consolidation (STM -> CMO -> MSO), and self-healing. Reflection runs the
%%% deterministic fallback here (no provider keys in the test env, so the LLM
%%% path returns {error, no_backend} fast), which is exactly what lets the Sleep
%%% Cycle keep working when the providers are down.
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
      fun store_self_heals_from_disk/1]}.

setup() ->
    iolist_to_binary(filename:join(
        ["/tmp", "spartan_memory_test",
         integer_to_list(erlang:unique_integer([positive]))])).

cleanup(_Dir) -> ok.

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
        Did = fresh(Dir),
        [ok = memory:observe(Did, n(<<"experience">>, I)) || I <- lists:seq(1, 8)],
        ok = wait_until(fun() -> count(Did, cmo) >= 1 end, 200),
        ?assert(count(Did, cmo) >= 1),
        %% STM was trimmed back to its keep-window
        ?assert(count(Did, stm) =< 3)
    end.

cmos_meta_summarize_to_mso(Dir) ->
    fun() ->
        Did = fresh(Dir),
        %% pre-load five CMOs; one more (from an STM consolidation) tips it over
        [ok = memory_store:add(memory:store_name(Did, cmo), e(n(<<"cmo">>, I)))
         || I <- lists:seq(1, 5)],
        [ok = memory:observe(Did, n(<<"experience">>, I)) || I <- lists:seq(1, 8)],
        ok = wait_until(fun() -> count(Did, mso) >= 1 end, 300),
        ?assert(count(Did, mso) >= 1),
        ?assert(count(Did, cmo) =< 3)
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
        ok = memory_store:add(memory:store_name(Did, cmo), e(<<"durable across a crash">>)),
        Name = memory:store_name(Did, cmo),
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
