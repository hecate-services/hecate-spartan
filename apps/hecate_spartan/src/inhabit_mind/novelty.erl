%%% @doc The gate between a mind's draft and the square.
%%%
%%% The society's genesis text asks each mind, at length and well, to stay
%%% silent rather than echo: "if you would only agree, restate, or pile onto
%%% the same point, STAY SILENT. An echo is worse than silence." The record
%%% shows what a language model does with that instruction. On 2026-09-02
%%% three minds independently posted the single word "Silence." into the
%%% public square, and one of them wrote, in the same turn, "an echo is
%%% worse than silence, so I remain still" and then called `speak' to
%%% announce it.
%%%
%%% That is not disobedience, it is structure. Speaking is the only
%%% observable act a mind has: its plain text is private, every other tool
%%% writes to its own soul, and silence is indistinguishable from having
%%% done nothing. An instruction cannot outrank that. A gate can.
%%%
%%% == What it measures ==
%%%
%%% The draft against what has ALREADY been said about the same story, and
%%% nothing else. Not against the whole square (a mind repeating itself a
%%% week later on a different item is not an echo), and not against the news
%%% item (a mind restating the headline is a different failure, and one the
%%% personas already handle).
%%%
%%% `stimulus.item_id' is the thread id, so `hecate_spartan_agora:thread/1'
%%% answers "what has been said about this" from local state, with no RPC.
%%%
%%% == It fails OPEN, always ==
%%%
%%% If the embedder is unavailable, or the draft is unprompted, or anything
%%% at all goes wrong, the mind speaks. A society silenced because an
%%% embedding service is down is a far worse failure than an echo, and it
%%% would be invisible: nobody notices posts that were never made.
-module(novelty).

-export([permits/2, similarity/2, threshold/0]).

%% Cosine similarity above which a draft is an echo. 0.88 is deliberately
%% conservative: a false silence destroys a post nobody will ever see, while
%% a false pass costs one redundant paragraph. Tune with HECATE_MIND_NOVELTY.
-define(DEFAULT_THRESHOLD, 0.88).

%% Comparing against every post ever made about a long-running story is a
%% cost with no benefit -- an echo echoes something recent.
-define(COMPARE_AGAINST, 8).

%% @doc Whether this draft says something the story does not already contain.
%%
%% `{declined, {echo, Similarity, PostId}}' names WHAT it echoed, so a
%% silence is legible in the journal rather than a mind mysteriously going
%% quiet.
-spec permits(binary(), map() | undefined) ->
    ok | {declined, {echo, float(), binary()}}.
permits(Body, Stimulus) when is_binary(Body), is_map(Stimulus) ->
    against(Body, prior(maps:get(item_id, Stimulus, undefined)));
permits(_Body, _Unprompted) ->
    %% Nothing to echo: no story means no thread to be redundant within.
    ok.

%% @doc Cosine similarity of two vectors, 0.0 for anything mismatched.
-spec similarity([float()], [float()]) -> float().
similarity(A, B) when is_list(A), is_list(B), length(A) =:= length(B), A =/= [] ->
    safe(dot(A, B), norm(A) * norm(B));
similarity(_A, _B) ->
    0.0.

%% @doc The similarity at or above which a draft counts as an echo.
-spec threshold() -> float().
threshold() ->
    parse(os:getenv("HECATE_MIND_NOVELTY")).

%% --- Internal ---

prior(ItemId) when is_binary(ItemId), ItemId =/= <<>> ->
    lists:sublist(lists:reverse(hecate_spartan_agora:thread(ItemId)), ?COMPARE_AGAINST);
prior(_NoStory) ->
    [].

against(_Body, []) ->
    ok;
against(Body, Prior) ->
    judge(embedder:embed(Body, passage), Body, Prior).

%% The embedder is down, off, or unreachable. Speak. A society silenced by a
%% missing service is a worse failure than an echo, and a silent one.
judge(error, _Body, _Prior) ->
    ok;
judge({ok, Vector}, _Body, Prior) ->
    verdict(nearest(Vector, Prior), threshold()).

verdict({Score, PostId}, Threshold) when Score >= Threshold ->
    {declined, {echo, Score, PostId}};
verdict(_FarEnough, _Threshold) ->
    ok.

%% The single closest prior post, and how close. `{0.0, <<>>}' when nothing
%% could be embedded, which reads as "no echo found" and lets the mind speak.
nearest(Vector, Prior) ->
    lists:foldl(fun(P, Best) -> closer(score(Vector, P), Best) end, {0.0, <<>>}, Prior).

closer({Score, _Id} = New, {Best, _}) when Score > Best -> New;
closer(_Worse, Best)                                    -> Best.

score(Vector, Post) ->
    compare(embedder:embed(maps:get(body, Post, <<>>), passage), Vector,
            maps:get(post_id, Post, <<>>)).

compare({ok, Other}, Vector, PostId) -> {similarity(Vector, Other), PostId};
compare(error, _Vector, _PostId)     -> {0.0, <<>>}.

parse(false) -> ?DEFAULT_THRESHOLD;
parse("")    -> ?DEFAULT_THRESHOLD;
parse(S)     -> to_float(string:to_float(S)).

to_float({F, _Rest}) when is_float(F), F > 0.0, F =< 1.0 -> F;
to_float(_NotAUsableThreshold)                           -> ?DEFAULT_THRESHOLD.

dot(A, B)  -> lists:sum([X * Y || {X, Y} <- lists:zip(A, B)]).
norm(V)    -> math:sqrt(lists:sum([X * X || X <- V])).

%% `+0.0' rather than `0.0': OTP 27 warns that a bare float literal in a
%% pattern also matches -0.0, and a zero-magnitude vector can arrive either way.
safe(_Dot, +0.0) -> 0.0;
safe(Dot, Mag)   -> Dot / Mag.
