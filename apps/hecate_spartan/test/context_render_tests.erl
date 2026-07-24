%%% @doc DEFECT 1, the charter black hole.
%%%
%%% Soul archives the mind APPENDS to were rendered with `clip_head'. Past the
%%% budget that renders only the founding block, forever: every later amendment is
%%% written to disk, acknowledged to the mind as done, and never read again.
%%% Constitutional self-authorship silently became a no-op, and nothing anywhere
%%% said so.
%%%
%%% Two archives had it: `charter' and `philosophy' — both appended, both clipped
%%% head-only. Two more faded from the other end (`genesis_addendum',
%%% `knowledge_map'). All four now keep both ends with the elision named.
-module(context_render_tests).

-include_lib("eunit/include/eunit.hrl").

%% Comfortably past every per-blob budget (the largest is 2000).
filler() -> binary:copy(<<"padding padding padding\n">>, 400).

render(Soul) ->
    iolist_to_binary([maps:get(content, M) || M <- context_assembler:render(#{soul => Soul})]).

contains(H, N) -> binary:match(H, N) =/= nomatch.

sandwich(First, Last) ->
    <<First/binary, "\n", (filler())/binary, "\n", Last/binary>>.

%% --- the black hole itself ---

late_charter_amendment_is_rendered_test() ->
    Out = render(#{charter => sandwich(<<"I exist to be useful.">>,
                                       <<"I now refuse unsourced claims.">>)}),
    ?assert(contains(Out, <<"I exist to be useful.">>)),
    ?assert(contains(Out, <<"I now refuse unsourced claims.">>)).

late_philosophy_entry_is_rendered_test() ->
    Out = render(#{philosophy => sandwich(<<"The world is knowable.">>,
                                          <<"Certainty is usually a smell.">>)}),
    ?assert(contains(Out, <<"The world is knowable.">>)),
    ?assert(contains(Out, <<"Certainty is usually a smell.">>)).

%% The other direction: these clipped the tail, so the OLDEST entries vanished
%% while remaining nominally adopted.
early_adopted_principle_is_rendered_test() ->
    Out = render(#{genesis_addendum => sandwich(<<"Always cite the source.">>,
                                                <<"Prefer the plainer word.">>)}),
    ?assert(contains(Out, <<"Always cite the source.">>)),
    ?assert(contains(Out, <<"Prefer the plainer word.">>)).

early_knowledge_map_title_is_rendered_test() ->
    Out = render(#{knowledge_map => sandwich(<<"- On tides">>, <<"- On harbours">>)}),
    ?assert(contains(Out, <<"On tides">>)),
    ?assert(contains(Out, <<"On harbours">>)).

%% --- the mind can see that it happened ---

%% The marker is in-context rather than in the HUD on purpose: the mind reads,
%% inside its own charter, that something was elided.
elision_is_named_in_context_test() ->
    Out = render(#{charter => sandwich(<<"first">>, <<"last">>)}),
    ?assert(contains(Out, <<"characters elided from the middle">>)).

%% --- and nothing changes for a blob that fits ---

a_short_charter_is_untouched_test() ->
    Out = render(#{charter => <<"## PRINCIPLE\n\nSay less.\n">>}),
    ?assert(contains(Out, <<"Say less.">>)),
    ?assertNot(contains(Out, <<"elided">>)).

%% Pure logs stay tail-clipped, which is honest: a new entry is always visible and
%% only old ones fade. Guard against someone "fixing" these too.
lessons_keep_the_newest_test() ->
    Out = render(#{lessons => sandwich(<<"an ancient lesson">>, <<"a fresh lesson">>)}),
    ?assert(contains(Out, <<"a fresh lesson">>)).
