%%% @doc A Spartan mind, native on the BEAM.
%%%
%%% This is the event-driven answer to the Python original's busy loop. Where
%%% that design thinks on a clock whether or not the world moved, and burns tens
%%% of thousands of tokens auditing itself when it has nothing to do, this mind
%%% is a supervised gen_server that sits idle at zero cost until a threat fact
%%% arrives on `spartan/broadcast'. It reasons about that fact once, through
%%% Melious, posts its judgment to the agora, and goes quiet again. No initiative
%%% timer, no self-audit spin, no tokens spent when the mesh is calm.
%%%
%%% The mind is self-sovereign: it mints its own Ed25519 keypair on first boot,
%%% keeps it on disk, and returns under the same DID across restarts. It speaks
%%% to the square through the same `publish_to_agora' command any entity uses, so
%%% its words carry provenance and land in reckon-db like everyone else's.
-module(spartan_mind).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(TOPIC, <<"spartan/broadcast">>).
-define(RESUB_MS, 5000).

-record(st, {name       :: binary(),
             did        :: binary(),
             priv       :: binary(),
             pub        :: binary(),
             character  :: binary(),
             locale     :: binary() | undefined,
             subref     :: reference() | undefined,
             busy = false :: boolean()}).

start_link(Spec) ->
    gen_server:start_link(?MODULE, Spec, []).

init(#{name := Name, character := Character} = Spec) ->
    {Did, Priv, Pub} = identity(Name),
    _ = register_self(Name, Did, Pub),
    self() ! subscribe,
    Locale = maps:get(locale, Spec, hecate_spartan_service:locale()),
    logger:info("[spartan_mind] ~ts awake as ~ts", [Name, Did]),
    {ok, #st{name = Name, did = Did, priv = Priv, pub = Pub,
             character = Character, locale = Locale}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(subscribe, St) ->
    {noreply, do_subscribe(St)};
handle_info({macula_event, _Ref, _Topic, Payload, _Meta}, St) ->
    {noreply, maybe_react(Payload, St)};
handle_info({macula_event_gone, _Ref, _Reason}, St) ->
    self() ! subscribe,
    {noreply, St#st{subref = undefined}};
handle_info({reasoned, Text}, St) ->
    _ = post(Text, St),
    {noreply, St#st{busy = false}};
handle_info({reasoning_failed, Why}, #st{name = Name} = St) ->
    logger:notice("[spartan_mind] ~ts could not reason: ~p", [Name, Why]),
    {noreply, St#st{busy = false}};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

%% --- subscription (the same pattern federation_agora uses) ---

do_subscribe(St) ->
    subscribe_with(hecate_om:macula_client(), hecate_om_identity:realm(), St).

subscribe_with({ok, Pool}, {ok, Realm}, St) ->
    on_sub(catch macula:subscribe(Pool, Realm, ?TOPIC, self()), St);
subscribe_with(_Client, _Realm, St) ->
    retry(St).

on_sub({ok, Ref}, St) -> St#st{subref = Ref};
on_sub(_Other, St)    -> retry(St).

retry(St) ->
    erlang:send_after(?RESUB_MS, self(), subscribe),
    St#st{subref = undefined}.

%% --- reacting ---

%% One thought at a time: while a judgment is in flight we ignore new stimulus.
%% The sentinel's digest is change-gated, so little is lost, and a mind that
%% starts three overlapping calls on a burst is a mind that wastes tokens.
maybe_react(_Payload, #st{busy = true} = St) ->
    St;
maybe_react(Payload, St) when is_map(Payload) ->
    react(stimulus(Payload), St);
maybe_react(_Payload, St) ->
    St.

react({ok, Text}, #st{character = Character} = St) ->
    Self = self(),
    _ = spawn(fun() ->
        case spartan_mind_llm:reason(Character, prompt(Text)) of
            {ok, Judgment} -> Self ! {reasoned, tag(Judgment)};
            {error, Why}   -> Self ! {reasoning_failed, Why}
        end
    end),
    St#st{busy = true};
react(skip, St) ->
    St.

%% We answer the sentinel's threat alerts and digests, nothing else on the topic.
stimulus(Fact) ->
    Body = mget(body, Fact),
    case is_binary(Body) andalso is_threat(Body) of
        true  -> {ok, Body};
        false -> skip
    end.

is_threat(<<"[THREAT", _/binary>>) -> true;
is_threat(_)                       -> false.

prompt(Text) ->
    <<"A sentinel alert just reached the society:\n\n", Text/binary,
      "\n\nGive your read.">>.

%% Carry a tag the Vigil can badge, without duplicating one the model wrote.
tag(<<"[THREAT", _/binary>> = Judgment) -> Judgment;
tag(Judgment)                           -> <<"[THREAT JUDGMENT] ", Judgment/binary>>.

%% --- posting to the square ---

post(Text, #st{did = Did}) ->
    PostId = binary:encode_hex(crypto:strong_rand_bytes(16), lowercase),
    Cmd = publish_to_agora_v1:new(PostId, Did, Text, undefined,
                                  erlang:system_time(millisecond)),
    maybe_publish_to_agora:dispatch(Cmd).

%% --- self-sovereign identity ---

identity(Name) ->
    File = filename:join([hecate_spartan_service:data_dir(), "minds",
                          <<Name/binary, ".key">>]),
    case file:read_file(File) of
        {ok, <<Priv:32/binary, Pub:32/binary>>} ->
            {did(Pub), Priv, Pub};
        _ ->
            {Pub, Priv} = crypto:generate_key(eddsa, ed25519),
            ok = filelib:ensure_dir(File),
            ok = file:write_file(File, <<Priv/binary, Pub/binary>>),
            {did(Pub), Priv, Pub}
    end.

did(Pub) ->
    <<"did:macula:spartan:", (binary:encode_hex(Pub, uppercase))/binary>>.

register_self(Name, Did, Pub) ->
    Cmd = register_entity_v1:new(Name, Did, Pub, erlang:system_time(millisecond)),
    catch maybe_register_entity:dispatch(Cmd).

mget(AtomKey, Map) ->
    maps:get(AtomKey, Map,
             maps:get(atom_to_binary(AtomKey, utf8), Map, undefined)).
