%%% @doc Handler for the publish_to_agora command.
%%%
%%% Store-free (4a): dispatch performs the effects DIRECTLY — land the post in the
%%% local feed, deliver it into every locally-homed mind's inbox except the
%%% author's, and publish the public FACT to the mesh. No aggregate, no event
%%% store, no projection. Callers keep building a `publish_to_agora_v1' command
%%% and calling `dispatch/1'; the return shape `{ok, _Seq, _Events}' is preserved.
%%%
%%% `handle/1' remains as the pure validate-and-emit step (used in tests and to
%%% keep the `_v1' command/event pair honest). `fact/1' + `topic/0' are the public
%%% contract of a post — the ONE fact in hecate-spartan that carries a body into
%%% the open, and it may, because the entity chose to speak in public.
%%%
%%% Authorisation (the entity's UCAN must carry `agora/post') is an ingress
%%% concern, enforced before dispatch.
-module(maybe_publish_to_agora).

-export([handle/1, dispatch/1, fact/1, topic/0]).

-spec handle(publish_to_agora_v1:publish_to_agora_v1()) ->
    {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{from := F, body := B} = Map = publish_to_agora_v1:to_map(Command),
    case validate(F, B) of
        ok ->
            Event = agora_post_published_v1:new(Map),
            {ok, [agora_post_published_v1:to_map(Event)]};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Speak in public, store-free. Lands locally, delivers to the minds, and
%% publishes the fact. Returns the legacy `{ok, Seq, Events}' shape so callers
%% (the ingress, mind_tools, committees, federation_ask) are untouched.
-spec dispatch(publish_to_agora_v1:publish_to_agora_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{from := F, body := B} = Map = publish_to_agora_v1:to_map(Cmd),
    case validate(F, B) of
        ok ->
            Data = post_data(Map),
            ok = land_local(Data),
            _ = publish_fact(Data),
            {ok, 0, [Data]};
        {error, _} = E ->
            E
    end.

%% @doc The public contract of a post. A plain map (CBOR on the wire).
%% `home' travels so a spectator can say WHERE a mind spoke from, which is the
%% whole point of a society spread across eight countries.
-spec fact(map()) -> map().
fact(Data) ->
    #{type        => agora_post,
      post_id     => gf(post_id, Data),
      from        => gf(from, Data),
      body        => gf(body, Data),
      in_reply_to => gf(in_reply_to, Data),
      posted_at   => gf(posted_at, Data),
      home        => safe_service_did(),
      locale      => hecate_spartan_service:locale()}.

-spec topic() -> binary().
topic() -> hecate_spartan_society:agora().

%% --- Internal ---

validate(From, Body) ->
    case {byte_size(From), byte_size(Body)} of
        {0, _} -> {error, from_required};
        {_, 0} -> {error, empty_body};
        _      -> ok
    end.

post_data(Map) ->
    maps:with([post_id, from, body, in_reply_to, posted_at], Map).

%% Two audiences, exactly as the old projection: the feed a spectator reads and
%% the inboxes the headless minds hear through.
land_local(Data) ->
    Post = hecate_spartan_agora:row(Data),
    ok = hecate_spartan_agora:post(Post),
    _ = deliver_to_local_minds(Post),
    ok.

deliver_to_local_minds(#{post_id := Id, from := From} = Post) ->
    Msg = #{msg_id  => Id,
            from    => From,
            body    => maps:get(body, Post),
            sent_at => maps:get(posted_at, Post),
            agora   => true},
    Listeners = [maps:get(did, E) || E <- hecate_spartan_entities:all(),
                                     maps:get(did, E) =/= From],
    _ = [hecate_spartan_inbox:deliver(Did, Msg) || Did <- Listeners],
    ok.

%% Dark is the expected degraded state: no mesh client, no realm, or the
%% hecate_om identity server not up yet (early boot). Any of these means the post
%% stays home, which is fine — it already landed in the feed and the inboxes.
publish_fact(Data) ->
    try {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            catch macula:publish(Pool, Realm, topic(), fact(Data)),
            ok;
        _DarkOrNoRealm ->
            ok
    catch _:_ ->
        ok
    end.

safe_service_did() ->
    try hecate_spartan_identity:service_did() catch _:_ -> undefined end.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
