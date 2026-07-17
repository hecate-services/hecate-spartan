%%% @doc One tier of the memory faculty: short-term (STM), condensed (CMO), or
%%% meta-summary (MSO). A gen_server holding an ordered list of entries, newest
%%% last, and owning a file so the tier survives a restart. Single writer, so no
%%% write conflict; reloads from disk on crash.
%%%
%%% An entry is `#{text := binary(), at := integer(), importance := integer()}'.
%%% Persisted as an Erlang term (the entries are machine state, not the mind's
%%% self-authored prose — that is the Soul's job).
-module(memory_store).
-behaviour(gen_server).

-export([start_link/1, add/2, recent/2, all/1, trim/2, count/1]).
-export([init/1, handle_call/3, handle_cast/2]).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(#{did := Did, tier := Tier} = Spec) ->
    gen_server:start_link({local, memory:store_name(Did, Tier)}, ?MODULE, Spec, []).

-spec add(gen_server:server_ref(), map()) -> ok.
add(Ref, Entry) -> gen_server:call(Ref, {add, Entry}).

%% @doc The most recent N entries (fewer if the tier is smaller), oldest first.
-spec recent(gen_server:server_ref(), non_neg_integer()) -> [map()].
recent(Ref, N) -> gen_server:call(Ref, {recent, N}).

-spec all(gen_server:server_ref()) -> [map()].
all(Ref) -> gen_server:call(Ref, all).

%% @doc Keep only the most recent Keep entries (consolidation trims the raw tier).
-spec trim(gen_server:server_ref(), non_neg_integer()) -> ok.
trim(Ref, Keep) -> gen_server:call(Ref, {trim, Keep}).

-spec count(gen_server:server_ref()) -> non_neg_integer().
count(Ref) -> gen_server:call(Ref, count).

init(#{path := Path} = Spec) ->
    {ok, Spec#{entries => load(Path)}}.

handle_call({add, Entry}, _From, #{path := Path, entries := Es} = S) ->
    Es2 = Es ++ [Entry],
    ok = persist(Path, Es2),
    {reply, ok, S#{entries := Es2}};
handle_call({recent, N}, _From, #{entries := Es} = S) ->
    {reply, lastn(N, Es), S};
handle_call(all, _From, #{entries := Es} = S) ->
    {reply, Es, S};
handle_call({trim, Keep}, _From, #{path := Path, entries := Es} = S) ->
    Es2 = lastn(Keep, Es),
    ok = persist(Path, Es2),
    {reply, ok, S#{entries := Es2}};
handle_call(count, _From, #{entries := Es} = S) ->
    {reply, length(Es), S};
handle_call(_Other, _From, S) ->
    {reply, {error, unknown_request}, S}.

handle_cast(_Msg, S) ->
    {noreply, S}.

%% --- disk (atomic; term-encoded) ---

load(Path) ->
    interpret_load(file:read_file(Path)).

interpret_load({ok, Bin})       -> binary_to_term(Bin);
interpret_load({error, enoent}) -> [].

persist(Path, Entries) ->
    Tmp = <<Path/binary, ".tmp">>,
    ok = file:write_file(Tmp, term_to_binary(Entries)),
    file:rename(Tmp, Path).

lastn(N, List) ->
    lists:nthtail(max(0, length(List) - N), List).
