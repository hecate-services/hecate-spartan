%%% @doc Projection: threat_sighted_v1 -> the threat read model, and — when an
%%% attacker crosses a border — into the generals' inboxes to be judged.
%%%
%%% This is the seam where dumb sensing becomes reasoning. A warden reports raw
%%% facts; the read model aggregates them; and the moment an IP is seen by a
%%% SECOND country, the projection hands the whole picture to the minds. What
%%% they do with it is theirs: a rule engine would blindly block, a general reads
%%% the usernames tried, weighs whether it looks targeted or like botnet noise,
%%% and says so in the agora. That judgement is the thing this whole system
%%% exists to produce.
-module(threat_sighted_v1_to_threats).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

-define(TABLE, threat_projection_checkpoint).

interested_in() ->
    [<<"threat_sighted_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => ?TABLE}),
    {ok, #{}, RM}.

project(#{data := Data} = Event, _Metadata, State, RM) ->
    case get_event_type(Event) of
        <<"threat_sighted_v1">> -> record(Data, State, RM);
        _                       -> {ok, State, RM}
    end;
project(_Event, _Metadata, State, RM) ->
    {ok, State, RM}.

record(Data, State, RM) ->
    Row = hecate_spartan_threats:row(Data),
    _ = alert_if_crossed(hecate_spartan_threats:record_sighting(Row), Row),
    {ok, RM2} = evoq_read_model:put(maps:get(source_ip, Row), noted, RM),
    {ok, State, RM2}.

%% Only cross-border attackers reach the minds. A single country's noise is a
%% firehose no general should have to read; a campaign sweeping the federation
%% is exactly what they should weigh in on.
alert_if_crossed(crossed_border, Row) ->
    deliver_to_generals(Row);
alert_if_crossed(noted, _Row) ->
    ok.

deliver_to_generals(#{source_ip := Ip}) ->
    {ok, Full} = hecate_spartan_threats:get(Ip),
    Countries = maps:size(maps:get(wardens, Full, #{})),
    Users = maps:get(usernames, Full, []),
    Body = iolist_to_binary(
        [<<"[THREAT] ">>, Ip,
         <<" is now attacking ">>, integer_to_binary(Countries),
         <<" of our countries (">>,
         integer_to_binary(maps:get(total_attempts, Full, 0)),
         <<" attempts). Usernames tried: ">>, join(Users),
         <<". Is this a targeted campaign or botnet noise? Your read.">>]),
    Msg = #{msg_id  => <<"threat-", Ip/binary>>,
            from    => <<"did:web:macula.io#warden">>,
            body    => Body,
            sent_at => erlang:system_time(millisecond),
            threat  => true},
    _ = [hecate_spartan_inbox:deliver(maps:get(did, E), Msg)
         || E <- hecate_spartan_entities:all()],
    ok.

join([])    -> <<"(none captured)">>;
join(Users) -> iolist_to_binary(lists:join(<<", ">>, lists:sublist(Users, 12))).

get_event_type(#{event_type := T}) -> T;
get_event_type(_)                  -> undefined.
