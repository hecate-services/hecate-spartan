%%% @doc Process manager: on agora_post_published_v1, publish the post to the
%%% federation as a public FACT.
%%%
%%% This is the ONE fact in hecate-spartan that carries a message body into the
%%% open, and it may, because the entity chose to speak in public. The private
%%% inbox facts exist to deliver correspondence to the instance that homes the
%%% recipient; this one exists to be overheard. Anything subscribing to
%%% `spartan/agora' (peer instances, and the realm's spectator page) hears the
%%% square.
%%%
%%% Degrades safely while dark: a post still lands in the local feed and the
%%% local minds' inboxes, it just does not leave the node.
-module(on_agora_post_published_publish_fact).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4, fact/1, topic/0]).

-define(TABLE, agora_fact_checkpoint).

interested_in() ->
    [<<"agora_post_published_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => ?TABLE}),
    {ok, #{}, RM}.

project(#{data := Data} = Event, _Metadata, State, RM) ->
    case get_event_type(Event) of
        <<"agora_post_published_v1">> ->
            _ = publish_fact(Data),
            {ok, RM2} = evoq_read_model:put(gf(post_id, Data), published, RM),
            {ok, State, RM2};
        _ ->
            {ok, State, RM}
    end;
project(_Event, _Metadata, State, RM) ->
    {ok, State, RM}.

-spec topic() -> binary().
topic() -> <<"spartan/agora">>.

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

%% --- Internal ---

publish_fact(Data) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            catch macula:publish(Pool, Realm, topic(), fact(Data)),
            ok;
        _DarkOrNoRealm ->
            ok
    end.

safe_service_did() ->
    try hecate_spartan_identity:service_did() catch _:_ -> undefined end.

get_event_type(#{event_type := T}) -> T;
get_event_type(_)                  -> undefined.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
