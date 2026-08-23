%%% @doc One committee drone: a single analytical lens, its own genuinely
%%% separate process, reached only through the committee's shared mesh
%%% topic — never called into directly by the coordinator (committee.erl).
%%% This is the "real delegation" half of a committee: where the old design
%%% had one process voicing five personas through completion calls it made
%%% on their behalf, each lens here is its own gen_server with its own
%%% mailbox, its own crash boundary, and its own reasoning call — much
%%% closer to a resident mind's react loop than a scripted character.
%%%
%%% Floor-controlled: the coordinator publishes a `floor' fact naming whose
%%% turn it is; only the named drone reasons and speaks, over the transcript
%%% it has been independently accumulating off the topic since it
%%% subscribed. Nobody hands a drone a transcript; it overhears one, the same
%%% way a resident mind overhears the agora. A drone's own contribution comes
%%% back around the topic like anyone else's before it lands in its
%%% transcript — there is no local shortcut, so "what I heard" is always
%%% exactly what the room actually published.
%%%
%%% No persistent Soul: a drone has no continuity to keep. It lives exactly
%%% as long as its committee and forgets everything the moment it stops.
-module(committee_drone).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
%% Pure helpers, exported for tests.
-export([messages/3]).

-define(RESUB_MS, 1000).

-record(ds, {name       :: binary(),
             lens       :: binary(),
             question   :: binary(),
             topic      :: binary(),
             transcript = [] :: [map()],
             subref     :: reference() | undefined}).

start_link(Spec) ->
    gen_server:start_link(?MODULE, Spec, []).

init(#{name := Name, lens := Lens, question := Question, topic := Topic}) ->
    self() ! subscribe,
    {ok, #ds{name = Name, lens = Lens, question = Question, topic = Topic}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(subscribe, St) ->
    {noreply, do_subscribe(St)};
handle_info({macula_event, _Ref, _Topic, Payload, _Meta}, St) ->
    {noreply, on_fact(Payload, St)};
handle_info({macula_event_gone, _Ref, _Reason}, St) ->
    self() ! subscribe,
    {noreply, St#ds{subref = undefined}};
handle_info({spoke, Text}, St) ->
    _ = publish_line(St, Text),
    {noreply, St};
handle_info({speak_failed, Why}, #ds{name = Name} = St) ->
    logger:notice("[committee_drone] ~ts fell silent: ~p", [Name, Why]),
    _ = publish_silence(St, Why),
    {noreply, St};
handle_info(stop_now, St) ->
    {stop, normal, St};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

%% --- subscribing to the committee's shared topic ---

do_subscribe(St) ->
    subscribe_with(hecate_om:macula_client(), hecate_om_identity:realm(), St).

subscribe_with({ok, Pool}, {ok, Realm}, #ds{topic = Topic} = St) ->
    on_sub(catch macula:subscribe(Pool, Realm, Topic, self()), St);
subscribe_with(_Client, _Realm, St) ->
    retry_subscribe(St).

on_sub({ok, Ref}, St) -> St#ds{subref = Ref};
on_sub(_Other, St)    -> retry_subscribe(St).

retry_subscribe(St) ->
    erlang:send_after(?RESUB_MS, self(), subscribe),
    St.

%% --- reacting to what the room says ---

on_fact(Fact, St) when is_map(Fact) ->
    dispatch(mget(type, Fact), Fact, St);
on_fact(_NotMap, St) ->
    St.

dispatch(Type, Fact, St) when Type =:= committee_line; Type =:= <<"committee_line">> ->
    remember(Fact, St);
dispatch(Type, Fact, #ds{name = Name} = St) when Type =:= floor; Type =:= <<"floor">> ->
    take_floor(mget(drone, Fact) =:= Name, St);
dispatch(Type, _Fact, St) when Type =:= adjourn; Type =:= <<"adjourn">> ->
    self() ! stop_now,
    St;
dispatch(_Other, _Fact, St) ->
    St.

remember(Fact, #ds{transcript = T} = St) ->
    Line = #{drone => mget(drone, Fact), text => mget(body, Fact)},
    St#ds{transcript = T ++ [Line]}.

%% --- taking the floor: reason for myself, in my OWN process ---

take_floor(false, St) ->
    St;
take_floor(true, #ds{name = Name, lens = Lens, question = Q, transcript = T} = St) ->
    Self = self(),
    Msgs = messages(#{name => Name, lens => Lens}, Q, T),
    _ = spawn(fun() -> speak(Self, Msgs) end),
    St.

speak(Self, Messages) ->
    case spartan_mind_llm:reason_messages(Messages) of
        {ok, Text} when is_binary(Text), Text =/= <<>> ->
            Self ! {spoke, string:trim(Text)};
        {ok, _Empty} ->
            Self ! {speak_failed, empty};
        {error, Why} ->
            Self ! {speak_failed, Why}
    end.

%% ===================================================================
%% Building this drone's own prompt (pure — tested without a live backend)
%% ===================================================================

%% @doc The messages for one drone's turn: its charter and lens, then the
%% exchange so far as IT overheard it (or an invitation to open).
-spec messages(map(), binary(), [map()]) -> [map()].
messages(#{name := Name, lens := Lens}, Question, Transcript) ->
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
    <<"The committee has said so far:\n\n", (committee:render_transcript(Transcript))/binary,
      "\n\nAdd your view.">>.

sys(Content) -> #{<<"role">> => <<"system">>, <<"content">> => Content}.
usr(Content) -> #{<<"role">> => <<"user">>,   <<"content">> => Content}.

%% ===================================================================
%% Reaching the mesh — a drone speaks for itself, never through the coordinator
%% ===================================================================

publish_line(#ds{topic = Topic, name = Name}, Text) ->
    publish(Topic, #{type => committee_line, drone => Name, body => Text,
                     at => erlang:system_time(millisecond)}).

publish_silence(#ds{topic = Topic, name = Name}, Why) ->
    publish(Topic, #{type => silence, drone => Name, reason => reason_bin(Why),
                     at => erlang:system_time(millisecond)}).

reason_bin(Reason) -> iolist_to_binary(io_lib:format("~p", [Reason])).

publish(Topic, Fact) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} -> catch macula:publish(Pool, Realm, Topic, Fact), ok;
        _DarkOrNoRealm            -> ok
    end.

%% ===================================================================
%% Helpers
%% ===================================================================

%% A fact crosses the mesh as CBOR, so a key (or, for a closed vocabulary
%% value like `type', the value itself) may arrive as an atom or a binary;
%% dispatch/3's guards try both, this just reads the key generically.
mget(AtomKey, Map) ->
    maps:get(AtomKey, Map, maps:get(atom_to_binary(AtomKey, utf8), Map, undefined)).
