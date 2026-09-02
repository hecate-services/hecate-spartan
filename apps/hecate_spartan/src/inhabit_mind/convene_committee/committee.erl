%%% @doc A committee: a bounded, paced deliberation among drone minds, convened
%%% by a Spartan when a matter deserves more than one voice.
%%%
%%% A committee is the society in miniature, but ephemeral and single-purpose.
%%% Its convener sets a question; the committee spins up a handful of DRONES,
%%% each a distinct analytical lens (the operator, the skeptic, the adversary,
%%% the historian, the economist), as genuinely SEPARATE processes reached only
%%% through a shared mesh topic — never called into directly. This module is
%%% the ORCHESTRATOR, not the author: it decides who is invited and whose turn
%%% it is (a `floor' fact naming one drone), then waits for that drone to speak
%%% for itself on the topic. It never generates a drone's words. The SCRIBE is
%%% different: it is this process's own synthesis duty on the convener's
%%% behalf, not a voice in the room, so it stays here.
%%%
%%% Earlier design: one process sequentially prompted five personas through its
%%% own completion calls and stitched the results together — a simulation of a
%%% discussion, not one. See committee_drone.erl for the real half.
%%%
%%% It is event-driven and BOUNDED by construction: a fixed number of rounds,
%%% then a final report and a clean stop. A drone thinks through the same
%%% provider carousel a mind does, so committees share the society's backends
%%% and their key pools.
-module(committee).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
%% Pure helpers, exported for tests.
-export([pick_drones/1, scribe_messages/2, render_transcript/1]).

-define(FLOOR_TIMEOUT_MS, 180000).
-define(DEFAULT_ROUNDS, 2).

-record(cs, {id          :: binary(),
             convener    :: binary(),
             topic       :: binary(),
             question    :: binary(),
             drones      :: [map()],
             drone_sup   :: pid(),
             transcript = [] :: [map()],
             round       = 0 :: non_neg_integer(),
             max_rounds  :: pos_integer(),
             cursor      = 1 :: pos_integer(),
             subref      :: reference() | undefined,
             floor_timer :: reference() | undefined}).

start_link(Spec) ->
    gen_server:start_link(?MODULE, Spec, []).

init(#{convener := Convener, question := Question} = Spec) ->
    Id = hex(),
    Topic = hecate_spartan_society:committee(Id),
    Drones = pick_drones(maps:get(drones, Spec, 3)),
    {ok, DroneSup} = committee_drone_sup:start_link(),
    lists:foreach(fun(D) -> start_drone(DroneSup, D, Question, Topic) end, Drones),
    logger:info("[committee] ~ts convened by ~ts: ~b drones on ~ts",
                [Id, Convener, length(Drones), snippet(Question)]),
    self() ! subscribe,
    {ok, #cs{id = Id, convener = Convener, topic = Topic,
             question = Question, drones = Drones, drone_sup = DroneSup,
             max_rounds = maps:get(max_rounds, Spec, ?DEFAULT_ROUNDS)}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(subscribe, St) ->
    {noreply, do_subscribe(St)};
handle_info({macula_event, _Ref, _Topic, Payload, _Meta}, St) ->
    {noreply, on_fact(Payload, St)};
handle_info({macula_event_gone, _Ref, _Reason}, St) ->
    self() ! subscribe,
    {noreply, St#cs{subref = undefined}};
handle_info(floor_timeout, St) ->
    {noreply, absorb_silence(timeout, St)};
handle_info(adjourn, St) ->
    {stop, normal, St};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, #cs{drone_sup = Sup}) ->
    %% A plain link does not propagate a NORMAL exit, so cleanup has to be
    %% deliberate: stop the drones with this committee, not orphan them.
    catch supervisor:stop(Sup),
    ok.

%% --- birthing the drones (this is the whole of "convening"; nothing else
%% here ever speaks on a drone's behalf) ---

start_drone(Sup, #{name := Name, lens := Lens}, Question, Topic) ->
    {ok, _Pid} = committee_drone_sup:start_drone(
        Sup, #{name => Name, lens => Lens, question => Question, topic => Topic}),
    ok.

%% --- observing the room: the coordinator hears everything the drones do ---

do_subscribe(St) ->
    subscribe_with(hecate_om:macula_client(), hecate_om_identity:realm(), St).

subscribe_with({ok, Pool}, {ok, Realm}, #cs{topic = Topic} = St) ->
    on_sub(catch macula:subscribe(Pool, Realm, Topic, self()), St);
subscribe_with(_Client, _Realm, St) ->
    retry_subscribe(St).

%% A fresh subscription is the room actually being open; open the floor for
%% round 1 only now, not at init, so the opening turn is never published to a
%% topic nobody (including the coordinator itself) is listening to yet.
on_sub({ok, Ref}, St) ->
    open_floor(St#cs{subref = Ref});
on_sub(_Other, St) ->
    retry_subscribe(St).

retry_subscribe(St) ->
    erlang:send_after(1000, self(), subscribe),
    St.

%% --- reacting to what the drones say ---

on_fact(Fact, St) when is_map(Fact) ->
    dispatch_fact(mget(type, Fact), Fact, St);
on_fact(_NotMap, St) ->
    St.

dispatch_fact(Type, Fact, St) when Type =:= committee_line; Type =:= <<"committee_line">> ->
    from_current_drone(mget(drone, Fact) =:= current_drone(St), Fact, St);
dispatch_fact(Type, Fact, St) when Type =:= silence; Type =:= <<"silence">> ->
    from_current_drone(mget(drone, Fact) =:= current_drone(St), silence, St);
dispatch_fact(_Other, _Fact, St) ->
    St.

%% Only the drone actually holding the floor can advance it. A stray or late
%% line from a drone whose turn already passed (the floor timeout already
%% moved on) is still on the topic for every drone's OWN transcript to pick
%% up (committee_drone.erl's remember/2 does not care whose turn it is), but
%% the COORDINATOR's own transcript (what the scribe reads) and its cursor
%% must not move a second time for one turn.
from_current_drone(false, _FactOrSilence, St) ->
    St;
from_current_drone(true, silence, St) ->
    absorb_silence(declined, cancel_floor_timer(St));
from_current_drone(true, Fact, #cs{id = Id} = St) ->
    Line = #{drone => mget(drone, Fact), text => mget(body, Fact)},
    logger:info("[committee] ~ts absorbed ~ts's turn", [Id, maps:get(drone, Line)]),
    advance(cancel_floor_timer(St#cs{transcript = St#cs.transcript ++ [Line]})).

current_drone(#cs{drones = Drones, cursor = Cursor}) ->
    #{name := Name} = lists:nth(Cursor, Drones),
    Name.

absorb_silence(Why, #cs{id = Id} = St) ->
    logger:notice("[committee] ~ts drone ~ts fell silent: ~p", [Id, current_drone(St), Why]),
    advance(St).

%% --- the floor: whose turn it is, published, never assumed ---

%% Cancels any timer already running before arming a fresh one: open_floor/1
%% can legitimately fire twice for the same turn (a resubscribe mid-round
%% re-announces the current floor, same as federation_registry's reannounce),
%% and without this an orphaned first timer would later fire stale and force
%% a second, wrong advance past whichever drone actually holds the floor.
open_floor(St) ->
    publish_floor(St),
    arm_floor_timer(cancel_floor_timer(St)).

publish_floor(#cs{topic = Topic} = St) ->
    Fact = #{type => floor, drone => current_drone(St), at => erlang:system_time(millisecond)},
    publish(Topic, Fact).

arm_floor_timer(St) ->
    Ref = erlang:send_after(?FLOOR_TIMEOUT_MS, self(), floor_timeout),
    St#cs{floor_timer = Ref}.

cancel_floor_timer(#cs{floor_timer = undefined} = St) ->
    St;
cancel_floor_timer(#cs{floor_timer = Ref} = St) ->
    _ = erlang:cancel_timer(Ref),
    St#cs{floor_timer = undefined}.

%% Advance the cursor. Wrapping past the last drone closes a round: the scribe
%% reports, and either the next round begins or the committee dissolves.
advance(#cs{cursor = Cursor, drones = Drones} = St) when Cursor < length(Drones) ->
    open_floor(St#cs{cursor = Cursor + 1});
advance(St) ->
    close_round(St#cs{cursor = 1}).

close_round(#cs{round = R, max_rounds = Max} = St) ->
    Round = R + 1,
    _ = report(St),
    proceed(Round >= Max, St#cs{round = Round}).

%% Adjournment is a message to self, not a return value: on_fact/2 and its
%% helpers return a plain state that handle_info wraps in {noreply, _}, so the
%% stop cannot ride back through them. The pending report has already been
%% published above.
proceed(true, #cs{id = Id, topic = Topic} = St) ->
    logger:info("[committee] ~ts adjourning after ~b rounds", [Id, St#cs.round]),
    publish(Topic, #{type => adjourn, at => erlang:system_time(millisecond)}),
    self() ! adjourn,
    St;
proceed(false, St) ->
    open_floor(St).

%% --- the scribe: the coordinator's own synthesis, not a voice in the room ---

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
%% Building prompts / choosing drones (pure — tested without a live backend)
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

%% @doc Render the transcript as "name: text" lines. Shared with
%% committee_drone.erl (a sibling in this slice) — each drone renders its own
%% overheard transcript the same way the scribe renders the whole one.
-spec render_transcript([map()]) -> binary().
render_transcript(Transcript) ->
    iolist_to_binary(lists:join(<<"\n\n">>,
        [[maps:get(drone, L), <<": ">>, maps:get(text, L)] || L <- Transcript])).

sys(Content) -> #{<<"role">> => <<"system">>, <<"content">> => Content}.
usr(Content) -> #{<<"role">> => <<"user">>,   <<"content">> => Content}.

%% ===================================================================
%% Reaching the mesh
%% ===================================================================

%% The report goes to the agora through the same command any mind's speech does,
%% so it carries provenance and lands in reckon-db like every post.
publish_report(Convener, Header, Body) ->
    Post = <<Header/binary, "\n\n", Body/binary>>,
    %% The convener's own synthesis of a committee, not a reaction to a signal.
    Cmd = publish_to_agora_v1:new(hex(), Convener, Post, undefined,
                                  erlang:system_time(millisecond), undefined, undefined),
    catch maybe_publish_to_agora:dispatch(Cmd),
    ok.

publish(Topic, Fact) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} -> catch macula:publish(Pool, Realm, Topic, Fact), ok;
        _DarkOrNoRealm            -> ok
    end.

%% ===================================================================
%% Helpers
%% ===================================================================

hex() ->
    binary:encode_hex(crypto:strong_rand_bytes(16), lowercase).

snippet(Bin) when is_binary(Bin) ->
    case byte_size(Bin) =< 80 of
        true  -> Bin;
        false -> <<(binary:part(Bin, 0, 80))/binary, "\xe2\x80\xa6">>
    end;
snippet(Other) ->
    Other.

%% A fact crosses the mesh as CBOR, so a key (or, for a closed vocabulary
%% value like `type', the value itself) may arrive as an atom or a binary; the
%% guards above try both, this just reads the key generically.
mget(AtomKey, Map) ->
    maps:get(AtomKey, Map, maps:get(atom_to_binary(AtomKey, utf8), Map, undefined)).
