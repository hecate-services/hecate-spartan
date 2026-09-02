%%% @doc What a mind was reacting to, carried with what it said.
%%%
%%% A mind reasons about exactly ONE stimulus per turn and it knows which
%%% one. Until now `speak' threw that away and published five fields, so the
%%% square was a wall of anonymous prose in which no two posts could be known
%%% to be about the same thing — while everything a reader wants (headline,
%%% source, category, tags, picture) already travelled on the sensor's fact,
%%% one hop upstream.
%%%
%%% == Attach, never ask ==
%%%
%%% The mind does not author this and is never prompted for it. This module
%%% COPIES the fact the mind was actually handed. Every field is therefore
%%% provenance rather than a claim, and cannot be hallucinated: a model asked
%%% to name its own sources invents them; a model that never touches the
%%% attachment cannot.
%%%
%%% == item_id is the thread id ==
%%%
%%% Every post carrying the same `item_id' is the same conversation. That is
%%% the whole reason this is the prerequisite for the engagement work: a
%%% thread needs no reply chain, a thread can be counted and therefore
%%% bounded, a draft can be compared against its own thread and therefore
%%% gated, and a full thread can be handed to a synthesizer.
%%%
%%% A stimulus is INHERITED when a mind reasons about a peer's agora post:
%%% two minds arguing about the same bomb are on the same story, and the
%%% thread must survive the conversation leaving the wire.
%%%
%%% `undefined' when a mind spoke unprompted — a committee, a visitor's
%%% question on `<ns>/ask', a self-alert, its own initiative. That is not an
%%% error and readers render it as plain speech, which is what it is.
%%%
%%% Pure. No process, no config, no I/O.
-module(agora_stimulus).

-export([of_fact/1, to_wire/1]).

-type stimulus() :: #{item_id      := binary(),
                      title        := binary(),
                      url          := binary(),
                      image_url    := binary(),
                      source       := binary(),
                      source_type  := binary(),
                      topic_class  := binary(),
                      topics       := [binary()],
                      emoji        := binary(),
                      lang         := binary(),
                      %% TWO countries, because they are two different facts and
                      %% the sensor knows them differently. `reporting_*' is who
                      %% told you, taken EXACTLY from the source's own config.
                      %% `subject_*' is what it is about, a gazetteer substring
                      %% sweep that errs toward a best guess. An Irish
                      %% broadcaster on Poland is the interesting case, and one
                      %% field cannot say it.
                      %%
                      %% Both the ISO-2 code and the name travel. The code is
                      %% what a flag and a filter need, and the NAME can be
                      %% missing while the code is present -- observed live:
                      %% al jazeera reports `reporting_country' `qa' with an
                      %% empty name, because qa is not in the gazetteer. A
                      %% name-only shape loses that item entirely.
                      reporting_country      := binary(),
                      reporting_country_name := binary(),
                      subject_country        := binary(),
                      subject_country_name   := binary(),
                      published_at := integer()}.
-export_type([stimulus/0]).

%% @doc The stimulus a fact represents, or `undefined' if it is not one.
%%
%% Two shapes qualify. A SENSOR fact (hecate-news) carries `item_id' and the
%% item's own fields, and is read directly. A peer's AGORA post carries a
%% whole `stimulus' already, and is inherited so a conversation about a story
%% stays attached to that story. Anything else — a broadcast, a mission, a
%% self-alert, an empty map — is `undefined'.
-spec of_fact(term()) -> stimulus() | undefined.
of_fact(Fact) when is_map(Fact) ->
    sensed(text(get(item_id, Fact)), Fact);
of_fact(_NotAMap) ->
    undefined.

sensed(<<>>, Fact)   -> inherited(get(stimulus, Fact));
sensed(ItemId, Fact) -> of_news_item(ItemId, Fact).

%% A peer's post already carries one. Re-read it through the same shaping, so
%% an inherited stimulus and a sensed one are indistinguishable downstream and
%% a malformed one cannot travel further than the mind that received it.
inherited(Carried) when is_map(Carried) ->
    of_news_item(text(get(item_id, Carried)), Carried);
inherited(_None) ->
    undefined.

of_news_item(<<>>, _Fact) ->
    undefined;
of_news_item(ItemId, Fact) ->
    #{item_id      => ItemId,
      title        => text(get(title, Fact)),
      url          => text(get(url, Fact)),
      image_url    => text(get(image_url, Fact)),
      source       => text(get(source, Fact)),
      source_type  => text(get(source_type, Fact)),
      topic_class  => text(get(topic_class, Fact)),
      topics       => tags(get(topics, Fact)),
      emoji        => text(get(emoji, Fact)),
      lang         => text(get(lang, Fact)),
      reporting_country      => lower(text(get(reporting_country, Fact))),
      reporting_country_name => text(get(reporting_country_name, Fact)),
      subject_country        => lower(text(get(subject_country, Fact))),
      subject_country_name   => text(get(subject_country_name, Fact)),
      published_at => whole(get(published_at, Fact))}.

%% @doc The stimulus as it goes onto the wire, or nothing at all.
%%
%% Returned as a map to be MERGED into the fact, so an unprompted post carries
%% no `stimulus' key rather than a null one: absent and empty are different
%% claims, and a reader should not have to tell them apart.
-spec to_wire(stimulus() | undefined) -> map().
to_wire(undefined)              -> #{};
to_wire(S) when is_map(S)       -> #{stimulus => S}.

%% --- Internal ---

%% Keys arrive as atoms or as binaries in the SAME map, depending on what the
%% receiving VM happens to know. Values arrive bare from a BEAM producer and
%% `{text, _}'-tagged from anything that tags on the way out.
get(AtomKey, Map) ->
    maps:get(AtomKey, Map, maps:get(atom_to_binary(AtomKey, utf8), Map, undefined)).

text({text, Bin}) when is_binary(Bin) -> Bin;
text(Bin) when is_binary(Bin)         -> Bin;
text(_AbsentOrNotText)                -> <<>>.

tags(List) when is_list(List) -> [T || Raw <- List, (T = text(Raw)) =/= <<>>];
tags(_NotAList)               -> [].

whole(N) when is_integer(N), N >= 0 -> N;
whole(_NotAWholeNumber)             -> 0.

%% ISO-3166-1 alpha-2, lowercased once here so every consumer can compare and
%% index without each deciding a case convention of its own.
lower(Bin) -> string:lowercase(Bin).
