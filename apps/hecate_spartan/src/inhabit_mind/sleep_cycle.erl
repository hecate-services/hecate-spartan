%%% @doc The Sleep Cycle: a mind's memory consolidation process.
%%%
%%% Gene Sher's Spartan condenses raw experience into Condensed Memory Objects
%%% (CMOs) and CMOs into Meta-Summary Objects (MSOs) so a long-lived mind
%%% remembers its life instead of forgetting it past a window. This is the
%%% BEAM-native realization: a dedicated process per mind that, when the raw
%%% short-term tier fills, reflects it into a CMO and trims it; and when CMOs
%%% accumulate, condenses them into an MSO.
%%%
%%% Reflection uses the mind's own LLM (spartan_mind_llm) to write an abstractive
%%% insight; if no backend is reachable it falls back to a deterministic
%%% condensation, so consolidation still runs (less eloquently) when the
%%% providers are down. Nudged after each turn; it decides when it is due.
%%%
%%% See docs/DESIGN_MIND_FACULTIES.md for the theory (Generative Agents'
%%% reflection, memory consolidation, the Common Model's declarative memory).
-module(sleep_cycle).
-behaviour(gen_server).

-export([start_link/1, nudge/1]).
-export([init/1, handle_cast/2, handle_call/3]).

%% Budgets: consolidate STM at STM_FULL entries, keeping STM_KEEP raw; likewise
%% for the meta level. Small so the effect is visible; tune later.
-define(STM_FULL, 8).
-define(STM_KEEP, 2).
-define(CMO_FULL, 6).
-define(CMO_KEEP, 2).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(#{did := Did} = Spec) ->
    gen_server:start_link({local, memory:sleep_name(Did)}, ?MODULE, Spec, []).

%% @doc Ask the mind to consider consolidating (fire and forget; non-blocking).
-spec nudge(gen_server:server_ref()) -> ok.
nudge(Ref) -> gen_server:cast(Ref, consolidate).

init(#{did := _Did} = Spec) ->
    {ok, Spec}.

handle_cast(consolidate, #{did := Did} = S) ->
    _ = catch consolidate(Did),
    {noreply, S};
handle_cast(_Msg, S) ->
    {noreply, S}.

handle_call(_Req, _From, S) ->
    {reply, ok, S}.

%% --- consolidation ---

consolidate(Did) ->
    Stm = memory:store_name(Did, stm),
    stm_step(memory_store:count(Stm) >= ?STM_FULL, Did, Stm).

stm_step(false, _Did, _Stm) ->
    ok;
stm_step(true, Did, Stm) ->
    Entries = memory_store:all(Stm),
    Cmo = reflect(<<"experiences">>, texts(Entries)),
    memory_store:add(memory:store_name(Did, cmo), entry(Cmo)),
    memory_store:trim(Stm, ?STM_KEEP),
    Cmos = memory:store_name(Did, cmo),
    cmo_step(memory_store:count(Cmos) >= ?CMO_FULL, Did, Cmos).

cmo_step(false, _Did, _Cmos) ->
    ok;
cmo_step(true, Did, Cmos) ->
    Entries = memory_store:all(Cmos),
    Mso = reflect(<<"condensed memories">>, texts(Entries)),
    memory_store:add(memory:store_name(Did, mso), entry(Mso)),
    memory_store:trim(Cmos, ?CMO_KEEP).

%% Reflect a set of texts into one insight. Abstractive via the LLM; a
%% deterministic join if no backend answers, so the tier still advances.
reflect(Kind, Texts) ->
    Joined = join(Texts),
    from_llm(catch spartan_mind_llm:reason_messages(prompt(Kind, Joined)), Joined).

from_llm({ok, Text}, _Joined) when is_binary(Text), Text =/= <<>> ->
    Text;
from_llm(_Failed, Joined) ->
    <<"(unreflected) ", Joined/binary>>.

prompt(Kind, Joined) ->
    [#{role => <<"system">>,
       content => <<"Consolidate the following ", Kind/binary,
                    " into one durable, first-person insight of two or three "
                    "sentences. Keep what will matter to you later; drop the "
                    "transient. Write only the insight.">>},
     #{role => <<"user">>, content => Joined}].

texts(Entries) ->
    [maps:get(text, E, <<>>) || E <- Entries].

join(Texts) ->
    iolist_to_binary(lists:join(<<"\n">>, Texts)).

entry(Text) ->
    #{text => Text, at => erlang:system_time(millisecond), importance => 5}.
