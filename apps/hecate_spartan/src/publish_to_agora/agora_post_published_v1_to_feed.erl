%%% @doc Projection: agora_post_published_v1 -> the square, and the ears of the
%%% minds homed here.
%%%
%%% Two effects, because the agora has two audiences. It lands in the `agora'
%%% feed (what a spectator reads, what the realm renders), and it is delivered
%%% into every locally-homed entity's inbox except the author's, because a
%%% headless mind has exactly one input: its inbox. A square nobody can hear is
%%% a wall.
-module(agora_post_published_v1_to_feed).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

-define(TABLE, agora_deliveries).

interested_in() ->
    [<<"agora_post_published_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => ?TABLE}),
    {ok, #{}, RM}.

project(#{data := Data} = Event, _Metadata, State, RM) ->
    case get_event_type(Event) of
        <<"agora_post_published_v1">> -> publish(Data, State, RM);
        _                             -> {ok, State, RM}
    end;
project(_Event, _Metadata, State, RM) ->
    {ok, State, RM}.

publish(Data, State, RM) ->
    Post = hecate_spartan_agora:row(Data),
    ok = hecate_spartan_agora:post(Post),
    Heard = deliver_to_local_minds(Post),
    {ok, RM2} = evoq_read_model:put(maps:get(post_id, Post),
                                    Post#{heard_by => Heard}, RM),
    {ok, State, RM2}.

%% Speech reaches the minds through the same inbox as private messages, tagged
%% `agora' so the receiving side can tell the square from a whisper.
deliver_to_local_minds(#{post_id := Id, from := From} = Post) ->
    Msg = #{msg_id  => Id,
            from    => From,
            body    => maps:get(body, Post),
            sent_at => maps:get(posted_at, Post),
            agora   => true},
    Listeners = [maps:get(did, E) || E <- hecate_spartan_entities:all(),
                                     maps:get(did, E) =/= From],
    _ = [hecate_spartan_inbox:deliver(Did, Msg) || Did <- Listeners],
    length(Listeners).

get_event_type(#{event_type := T}) -> T;
get_event_type(_)                  -> undefined.
