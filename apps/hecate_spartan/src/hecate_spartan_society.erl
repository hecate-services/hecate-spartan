%%% @doc A society is a topic namespace. Every pubsub topic a mind uses derives
%%% from it, so one codebase runs many use cases: `spartan' (the cyber society),
%%% `news' (a news society), and so on, side by side on the same realm.
%%%
%%% A node's minds belong to ONE society, chosen by `HECATE_SOCIETY' (default
%%% `spartan'). Sensors publish signals to `<ns>/feed'; minds discuss in
%%% `<ns>/agora'. Nothing else in the mind knows the use case — the persona is
%%% data, and the society is a namespace.
%%%
%%% See docs/DESIGN_SOCIETIES_AND_SENSORS.md.
-module(hecate_spartan_society).

-export([namespace/0, topic/1, feed/0, agora/0, inbox/1, committee/1,
         cap_resource/2, wildcard/0]).

%% @doc The society this node's minds belong to. Default `spartan'.
-spec namespace() -> binary().
namespace() ->
    case os:getenv("HECATE_SOCIETY") of
        S when is_list(S), S =/= "" -> unicode:characters_to_binary(S);
        _Unset                      -> <<"spartan">>
    end.

%% @doc A society topic: `<ns>/<leaf>'. e.g. topic(<<"agora">>) -> `spartan/agora'.
-spec topic(binary()) -> binary().
topic(Leaf) when is_binary(Leaf) ->
    <<(namespace())/binary, "/", Leaf/binary>>.

%% @doc The feed: signals from the world (sensors publish here; minds attend it).
-spec feed() -> binary().
feed() -> topic(<<"feed">>).

%% @doc The public square: where the minds discuss.
-spec agora() -> binary().
agora() -> topic(<<"agora">>).

%% @doc A per-entity inbox topic: `<ns>/inbox/<did>'.
-spec inbox(binary()) -> binary().
inbox(Did) when is_binary(Did) ->
    <<(namespace())/binary, "/inbox/", Did/binary>>.

%% @doc A committee sub-topic: `<ns>/committee/<id>'.
-spec committee(binary()) -> binary().
committee(Id) when is_binary(Id) ->
    <<(namespace())/binary, "/committee/", Id/binary>>.

%% @doc A UCAN capability resource path: `<ns>/<realm>/<leaf>'.
-spec cap_resource(binary(), binary()) -> binary().
cap_resource(Realm, Leaf) when is_binary(Realm), is_binary(Leaf) ->
    <<(namespace())/binary, "/", Realm/binary, "/", Leaf/binary>>.

%% @doc The society's whole namespace, for a service's requested scope.
-spec wildcard() -> binary().
wildcard() ->
    <<(namespace())/binary, "/*">>.
