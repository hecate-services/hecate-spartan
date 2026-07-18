%%% @doc Handler for the report_activity command.
%%%
%%% Store-free (4a): the pulse is pure mesh. dispatch validates and publishes the
%%% spartan_activity fact directly — no local state at all (an activity report is
%%% legible-to-spectators only; nothing here consumes it). No aggregate, no event
%%% store, no projection.
%%%
%%% `handle/1' + `handle_from_map/1' remain as the pure validate-and-emit step.
%%% `fact/1' + `topic/0' are the public contract. The `?KINDS' whitelist keeps a
%%% watcher's badges honest: an unknown kind is rejected, not rendered as a
%%% mystery.
-module(maybe_report_activity).

-export([handle/1, handle_from_map/1, dispatch/1, fact/1, topic/0]).

%% Kinds a watcher can colour differently. Anything else is rejected rather than
%% rendered as a mystery badge.
-define(KINDS, [<<"action">>, <<"thought">>, <<"speech">>, <<"model">>,
                <<"alert">>, <<"cycle">>]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{activity_id := I, did := D, kind := K, summary := S} = P) ->
    At = maps:get(at, P, erlang:system_time(millisecond)),
    handle(report_activity_v1:new(I, D, K, S, At));
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(report_activity_v1:report_activity_v1()) ->
    {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{did := D, kind := K, summary := S} = Map = report_activity_v1:to_map(Command),
    case validate(D, K, S) of
        ok              -> {ok, [activity_reported_v1:to_map(
                                   activity_reported_v1:new(Map))]};
        {error, Reason} -> {error, Reason}
    end.

%% @doc Report an activity, store-free: validate then publish the fact. Returns
%% the legacy `{ok, Seq, Events}' shape so the ingress caller is untouched.
-spec dispatch(report_activity_v1:report_activity_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{did := D, kind := K, summary := S} = Map = report_activity_v1:to_map(Cmd),
    case validate(D, K, S) of
        ok ->
            Data = activity_data(Map),
            _ = publish_fact(Data),
            {ok, 0, [Data]};
        {error, _} = E ->
            E
    end.

-spec topic() -> binary().
topic() -> hecate_spartan_society:topic(<<"activity">>).

-spec fact(map()) -> map().
fact(Data) ->
    #{type        => spartan_activity,
      activity_id => gf(activity_id, Data),
      did         => gf(did, Data),
      kind        => gf(kind, Data),
      summary     => gf(summary, Data),
      at          => gf(at, Data),
      locale      => hecate_spartan_service:locale()}.

%% --- Internal ---

validate(Did, Kind, Summary) ->
    case {byte_size(Did), lists:member(Kind, ?KINDS), byte_size(Summary)} of
        {0, _, _}     -> {error, did_required};
        {_, false, _} -> {error, unknown_kind};
        {_, _, 0}     -> {error, empty_summary};
        _             -> ok
    end.

activity_data(Map) ->
    maps:with([activity_id, did, kind, summary, at], Map).

%% Dark is the expected degraded state: no mesh client, no realm, or the
%% hecate_om identity server not up yet (early boot). The pulse is mesh-only, so
%% while dark a report simply is not seen — no local consumer to miss it.
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

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
