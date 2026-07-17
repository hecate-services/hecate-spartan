%%% @doc One area of consciousness.
%%%
%%% A mind's Soul is not a document and not an event stream — it is a small
%%% society of processes, one per faculty (charter, lessons, journal, grand
%%% strategy, ...). This is that process: a gen_server that owns exactly one
%%% Soul archive file and is its SOLE writer.
%%%
%%% Two consequences fall out of single-writer-per-area, both of which the
%%% event-sourced Soul lacked:
%%%
%%%   - No write conflict. There is one writer, so `wrong_expected_version'
%%%     (the failure the event-sourced soul threw) cannot occur by construction.
%%%   - Self-healing. The content lives in memory and on disk. If this process
%%%     crashes, its supervisor restarts it and `init/1' reloads the file — the
%%%     faculty comes back exactly as the disk last saw it, and no sibling
%%%     faculty is disturbed.
%%%
%%% Writes are atomic (write-temp then rename), so a crash mid-write can never
%%% leave a torn archive.
-module(soul_area).
-behaviour(gen_server).

-export([start_link/1, read/1, append/2, set/2]).
-export([init/1, handle_call/3, handle_cast/2]).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(#{did := Did, area := Area} = Spec) ->
    gen_server:start_link({local, soul:area_name(Did, Area)}, ?MODULE, Spec, []).

%% @doc Current content of the faculty (binary Markdown; empty if never written).
-spec read(gen_server:server_ref()) -> binary().
read(Ref) -> gen_server:call(Ref, read).

%% @doc Append a block to the faculty (charter entries, lessons, reflections).
-spec append(gen_server:server_ref(), binary()) -> ok.
append(Ref, Block) -> gen_server:call(Ref, {append, Block}).

%% @doc Replace the whole faculty (grand strategy, working memory).
-spec set(gen_server:server_ref(), binary()) -> ok.
set(Ref, Content) -> gen_server:call(Ref, {set, Content}).

init(#{path := Path} = Spec) ->
    {ok, Spec#{content => read_file(Path)}}.

handle_call(read, _From, #{content := Content} = S) ->
    {reply, Content, S};
handle_call({append, Block}, _From, #{path := Path, content := Content} = S) ->
    New = <<Content/binary, Block/binary>>,
    ok = write_atomic(Path, New),
    {reply, ok, S#{content := New}};
handle_call({set, Content}, _From, #{path := Path} = S) ->
    ok = write_atomic(Path, Content),
    {reply, ok, S#{content := Content}};
handle_call(_Other, _From, S) ->
    {reply, {error, unknown_request}, S}.

handle_cast(_Msg, S) ->
    {noreply, S}.

%% --- disk ---

read_file(Path) ->
    interpret_read(file:read_file(Path)).

interpret_read({ok, Bin})       -> Bin;
interpret_read({error, enoent}) -> <<>>.

%% Atomic replace: write a sibling temp file, then rename over the target.
%% rename/2 is atomic on a POSIX filesystem, so a reader never sees a half file
%% and a crash mid-write leaves the previous content intact.
write_atomic(Path, Bin) ->
    Tmp = <<Path/binary, ".tmp">>,
    ok = file:write_file(Tmp, Bin),
    file:rename(Tmp, Path).
