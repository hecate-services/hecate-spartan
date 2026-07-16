%%% @doc A committee: a bounded, paced deliberation among drone minds, convened
%%% by a Spartan when a matter deserves more than one voice.
%%%
%%% A committee is the society in miniature, but ephemeral and single-purpose.
%%% Its convener sets a question; the committee spins up a handful of DRONES,
%%% each a distinct analytical lens (the operator, the skeptic, the adversary,
%%% the historian, the economist). The drones speak in turn over a shared
%%% transcript, building on and challenging each other, and at the close of every
%%% round the SCRIBE distils the exchange into a report published to the agora,
%%% where the whole society and any spectator can read it.
%%%
%%% It is event-driven, like a mind: it costs nothing between turns. A turn is a
%%% self-scheduled `tick', paced a few seconds apart so a committee does not
%%% hammer the providers, and the LLM call for a turn runs in a spawned process
%%% so the committee never blocks. It is BOUNDED by construction: a fixed number
%%% of rounds, then a final report and a clean stop. A drone thinks through the
%%% same provider carousel a mind does, so committees share the society's five
%%% backends and their key pools.
-module(committee).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
%% Pure helpers, exported for tests.
-export([pick_drones/1, drone_messages/3, scribe_messages/2, render_transcript/1]).

-define(TICK_MS, 4000).
-define(TICK_JITTER_MS, 3000).
-define(DEFAULT_ROUNDS, 2).
-define(TOPIC_PREFIX, <<"spartan/committee/">>).

-record(cs, {id          :: binary(),
             convener    :: binary(),
             topic       :: binary(),
             question    :: binary(),
             drones      :: [map()],
             transcript = [] :: [map()],
             round       = 0 :: non_neg_integer(),
             max_rounds  :: pos_integer(),
             cursor      = 1 :: pos_integer(),
             busy        = false :: boolean()}).

start_link(Spec) ->
    gen_server:start_link(?MODULE, Spec, []).

init(#{convener := Convener, question := Question} = Spec) ->
    Id = hex(),
    Drones = pick_drones(maps:get(drones, Spec, 3)),
    logger:info("[committee] ~ts convened by ~ts: ~b drones on ~ts",
                [Id, Convener, length(Drones), snippet(Question)]),
    schedule_tick(),
    {ok, #cs{id = Id, convener = Convener, topic = <<?TOPIC_PREFIX/binary, Id/binary>>,
             question = Question, drones = Drones,
             max_rounds = maps:get(max_rounds, Spec, ?DEFAULT_ROUNDS)}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

%% A turn: the drone at the cursor thinks over the transcript so far. The call
%% runs off-process so the committee stays responsive; the result comes back as
%% a contribution message. One turn in flight at a time.
handle_info(tick, #cs{busy = true} = St) ->
    {noreply, St};
handle_info(tick, St) ->
    {noreply, run_turn(St)};
handle_info({contribution, Drone, Text}, St) ->
    {noreply, absorb(Drone, Text, St)};
handle_info({contribution_failed, Drone, Why}, #cs{id = Id} = St) ->
    logger:notice("[committee] ~ts drone ~ts fell silent: ~p", [Id, Drone, Why]),
    {noreply, advance(St#cs{busy = false})};
handle_info(adjourn, St) ->
    {stop, normal, St};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

%% --- a drone's turn ---

run_turn(#cs{drones = Drones, cursor = Cursor, question = Q, transcript = T} = St) ->
    Drone = lists:nth(Cursor, Drones),
    Self = self(),
    Messages = drone_messages(Drone, Q, T),
    _ = spawn(fun() -> think(Self, Drone, Messages) end),
    St#cs{busy = true}.

think(Self, #{name := Name}, Messages) ->
    case spartan_mind_llm:reason_messages(Messages) of
        {ok, Text} when is_binary(Text), Text =/= <<>> ->
            Self ! {contribution, Name, string:trim(Text)};
        {ok, _Empty} ->
            Self ! {contribution_failed, Name, empty};
        {error, Why} ->
            Self ! {contribution_failed, Name, Why}
    end.

%% A contribution lands: record it, let the committee overhear it on its topic,
%% then advance the deliberation.
absorb(Drone, Text, #cs{transcript = T, topic = Topic} = St) ->
    Line = #{drone => Drone, text => Text},
    _ = publish_line(Topic, St#cs.id, Line),
    advance(St#cs{transcript = T ++ [Line], busy = false}).

%% Advance the cursor. Wrapping past the last drone closes a round: the scribe
%% reports, and either the next round begins or the committee dissolves.
advance(#cs{cursor = Cursor, drones = Drones} = St) when Cursor < length(Drones) ->
    schedule_tick(),
    St#cs{cursor = Cursor + 1};
advance(St) ->
    close_round(St#cs{cursor = 1}).

close_round(#cs{round = R, max_rounds = Max} = St) ->
    Round = R + 1,
    _ = report(St),
    proceed(Round >= Max, St#cs{round = Round}).

%% Adjournment is a message to self, not a return value: absorb/advance return a
%% plain state that handle_info wraps in {noreply, _}, so the stop cannot ride
%% back through them. The pending report has already been published above.
proceed(true, #cs{id = Id} = St) ->
    logger:info("[committee] ~ts adjourning after ~b rounds", [Id, St#cs.round]),
    self() ! adjourn,
    St;
proceed(false, St) ->
    schedule_tick(),
    St.

%% --- the scribe ---

%% The scribe reads the whole exchange and publishes the committee's report to
%% the agora, under the convener's name (a mind reports on behalf of the
%% committee it called). One report per round: the society sees the deliberation
%% converge, not just a verdict at the end.
report(#cs{transcript = []}) ->
    ok;
report(#cs{convener = Convener, question = Q, transcript = T, round = R, id = Id}) ->
    case spartan_mind_llm:reason_messages(scribe_messages(Q, T)) of
        {ok, Text} when is_binary(Text), Text =/= <<>> ->
            publish_report(Convener, header(Q, R + 1), string:trim(Text));
        _NoReport ->
            logger:notice("[committee] ~ts scribe produced nothing", [Id]),
            ok
    end.

header(Q, Round) ->
    <<"[COMMITTEE \xc2\xb7 round ", (integer_to_binary(Round))/binary, "] ", (snippet(Q))/binary>>.

%% ===================================================================
%% Building the prompts (pure — tested without a live backend)
%% ===================================================================

%% @doc Choose N drones from the lens roster, clamped to what exists.
-spec pick_drones(integer()) -> [map()].
pick_drones(N) when is_integer(N), N > 0 ->
    Lenses = lenses(),
    [#{name => Name, lens => Lens}
     || {Name, Lens} <- lists:sublist(Lenses, min(N, length(Lenses)))];
pick_drones(_) ->
    pick_drones(3).

%% The analytical lenses a committee draws its drones from. Each is a genuinely
%% different way of looking, so the deliberation has friction rather than echo.
lenses() ->
    [{<<"the operator">>,
      <<"You judge everything by what a defender must DO right now. You want "
        "concrete moves: block this range, rotate that credential, raise this "
        "posture. Vagueness is your enemy.">>},
     {<<"the skeptic">>,
      <<"You distrust tidy narratives and jumped-to conclusions. You ask what "
        "the evidence actually supports, what is assumed, and how the committee "
        "could be wrong. You puncture false confidence.">>},
     {<<"the adversary">>,
      <<"You think like the attacker. You ask what they are really after, what "
        "they try next, and how any defence proposed here would be evaded. You "
        "are the red team in the room.">>},
     {<<"the historian">>,
      <<"You place what is happening in the pattern of what came before. You ask "
        "whether this fits a known campaign, actor, or technique, and what that "
        "precedent tells the committee to expect.">>},
     {<<"the economist">>,
      <<"You weigh cost, effort, and scarce attention. You ask whether a "
        "response is worth its price, what it trades away, and where the "
        "committee's limited energy should actually go.">>}].

%% @doc The messages for one drone's turn: its charter and lens, then the
%% exchange so far (or an invitation to open).
-spec drone_messages(map(), binary(), [map()]) -> [map()].
drone_messages(#{name := Name, lens := Lens}, Question, Transcript) ->
    [sys(<<"You are a drone on a committee convened to deliberate a single "
           "question. You are one voice among several, each with a different "
           "lens. Speak as ", Name/binary, ". ", Lens/binary, "\n\nBe brief and "
           "concrete: a few sentences, not an essay. Add something the others "
           "have not. Build on what is right, say plainly what is wrong, and "
           "never merely agree. The committee's question:\n\n", Question/binary>>),
     usr(opener(Transcript))].

opener([]) ->
    <<"You speak first. Open the committee's analysis.">>;
opener(Transcript) ->
    <<"The committee has said so far:\n\n", (render_transcript(Transcript))/binary,
      "\n\nAdd your view.">>.

%% @doc The scribe's messages: distil the exchange into an actionable report.
-spec scribe_messages(binary(), [map()]) -> [map()].
scribe_messages(Question, Transcript) ->
    [sys(<<"You are the scribe of a committee. Read the deliberation and write "
           "the committee's report: what it concludes and, above all, what "
           "should be DONE and how urgently. Be concrete and specific. Synthesize; "
           "do not transcribe. Keep it tight, a short briefing a reader can act "
           "on. The question was:\n\n", Question/binary>>),
     usr(<<"The deliberation:\n\n", (render_transcript(Transcript))/binary,
           "\n\nWrite the report.">>)].

%% @doc Render the transcript as "name: text" lines.
-spec render_transcript([map()]) -> binary().
render_transcript(Transcript) ->
    iolist_to_binary(lists:join(<<"\n\n">>,
        [[maps:get(drone, L), <<": ">>, maps:get(text, L)] || L <- Transcript])).

sys(Content) -> #{<<"role">> => <<"system">>, <<"content">> => Content}.
usr(Content) -> #{<<"role">> => <<"user">>,   <<"content">> => Content}.

%% ===================================================================
%% Reaching the mesh
%% ===================================================================

%% Drone lines are ephemeral integration facts on the committee's own topic, for
%% anyone who wants to watch a committee think (a /vigil committee view later).
%% They are not event-sourced: the durable record is the scribe's agora report.
publish_line(Topic, Id, #{drone := Drone, text := Text}) ->
    Fact = #{type => committee_line, committee => Id, drone => Drone, body => Text,
             at => erlang:system_time(millisecond)},
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} -> catch macula:publish(Pool, Realm, Topic, Fact), ok;
        _DarkOrNoRealm            -> ok
    end.

%% The report goes to the agora through the same command any mind's speech does,
%% so it carries provenance and lands in reckon-db like every post.
publish_report(Convener, Header, Body) ->
    Post = <<Header/binary, "\n\n", Body/binary>>,
    Cmd = publish_to_agora_v1:new(hex(), Convener, Post, undefined,
                                  erlang:system_time(millisecond)),
    catch maybe_publish_to_agora:dispatch(Cmd),
    ok.

%% ===================================================================
%% Helpers
%% ===================================================================

schedule_tick() ->
    erlang:send_after(?TICK_MS + rand:uniform(?TICK_JITTER_MS), self(), tick).

hex() ->
    binary:encode_hex(crypto:strong_rand_bytes(16), lowercase).

snippet(Bin) when is_binary(Bin) ->
    case byte_size(Bin) =< 80 of
        true  -> Bin;
        false -> <<(binary:part(Bin, 0, 80))/binary, "\xe2\x80\xa6">>
    end;
snippet(Other) ->
    Other.
