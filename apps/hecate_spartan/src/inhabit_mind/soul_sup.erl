%%% @doc A mind's Soul, as a supervision tree.
%%%
%%% One supervisor per mind; one child per area of consciousness. "Dividing the
%%% mind into areas of consciousness" is not a metaphor here — it is the process
%%% structure. Each faculty is supervised independently: a crash in one restarts
%%% that faculty alone (reloading its file), and the rest of the mind carries on.
%%%
%%% Started by `soul:open/3` when a mind boots, linked to the mind process, so
%%% the Soul lives and dies with the mind that inhabits it. The archive files on
%%% disk outlive any restart.
-module(soul_sup).
-behaviour(supervisor).

-export([start_link/2, init/1]).

-spec start_link(binary(), binary()) -> {ok, pid()} | {error, term()}.
start_link(Did, Dir) ->
    supervisor:start_link(?MODULE, {Did, Dir}).

init({Did, Dir}) ->
    Children = [area_child(Did, Dir, Area, File) || {Area, File} <- soul:areas()],
    {ok, {#{strategy => one_for_one, intensity => 10, period => 60}, Children}}.

area_child(Did, Dir, Area, File) ->
    #{id      => Area,
      start   => {soul_area, start_link,
                  [#{did => Did, area => Area,
                     path => iolist_to_binary(filename:join(Dir, File))}]},
      restart => permanent,
      type    => worker}.
