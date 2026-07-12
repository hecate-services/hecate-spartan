%%% @doc Process manager: on message_routed_v1, publish an integration FACT to
%%% the recipient's realm inbox topic.
%%%
%%% This is the federation seam. Delivery to entities homed on THIS instance is
%%% the in-process inbox (message_routed_v1_to_inbox). The mesh fact is the
%%% explicit, stable public contract that lets a PEER hecate-spartan instance
%%% deliver to an entity homed there — it is NOT a bridge of the internal
%%% domain event.
%%%
%%% Forward-compat: emitted now so federation lights up once cross-relay
%%% PubSub propagation is fixed upstream. Degrades safely while the service is
%%% dark (no mesh client / no realm) — the message still delivers locally.
-module(on_message_routed_publish_fact).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4, fact/1, topic/2]).

-define(TABLE, routed_fact_checkpoint).

interested_in() ->
    [<<"message_routed_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => ?TABLE}),
    {ok, #{}, RM}.

project(#{data := Data} = Event, _Metadata, State, RM) ->
    case get_event_type(Event) of
        <<"message_routed_v1">> ->
            _ = publish_fact(Data),
            {ok, RM2} = evoq_read_model:put(gf(msg_id, Data), published, RM),
            {ok, State, RM2};
        _ ->
            {ok, State, RM}
    end;
project(_Event, _Metadata, State, RM) ->
    {ok, State, RM}.

%% @doc The public integration-fact contract for a routed message. A plain map
%% (CBOR on the wire — never JSON-encoded).
-spec fact(map()) -> map().
fact(Data) ->
    #{type    => spartan_message,
      msg_id  => gf(msg_id, Data),
      from    => gf(from, Data),
      to      => gf(to, Data),
      body    => gf(body, Data),
      sent_at => gf(sent_at, Data)}.

%% @doc Realm inbox topic for a recipient DID (realm scoping is the publish
%% arg, so the topic itself is relative).
-spec topic(binary(), binary()) -> binary().
topic(_Realm, To) ->
    <<"spartan/inbox/", To/binary>>.

%% --- Internal ---

publish_fact(Data) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            Topic = topic(Realm, gf(to, Data)),
            catch macula:publish(Pool, Realm, Topic, fact(Data)),
            ok;
        _DarkOrNoRealm ->
            ok
    end.

get_event_type(#{event_type := T}) -> T;
get_event_type(_)                  -> undefined.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
