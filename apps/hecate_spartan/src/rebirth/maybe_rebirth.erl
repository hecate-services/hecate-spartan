%%% @doc Rebirth a node's mind(s) — a clean slate — the gitops way, no ssh.
%%%
%%% Set HECATE_SPARTAN_REBIRTH to a token (e.g. a date) in the node's committed
%%% env and push: on the next boot the mind wipes its data_dir (Soul, chronicle,
%%% memory, keypair) BEFORE anything opens it, so it comes up with no history and
%%% a fresh identity — same name (from env), new soul. Idempotent: a marker
%%% records the token that last fired, so a restart with the same token is a
%%% no-op. Change the token to rebirth again; clear it to stop.
%%%
%%% This replaces the old `deploy-spartan.sh WIPE=1' ssh path: the reset now
%%% travels through the pull reconciler like any other config, and watchtower
%%% rolls the image — nothing is done to a box by hand.
%%%
%%% Best-effort: called under a catch at service start, so a wipe failure never
%%% blocks the mind from booting.
-module(maybe_rebirth).

-export([maybe_rebirth/0]).

-define(MARKER, ".rebirth").

-spec maybe_rebirth() -> ok.
maybe_rebirth() ->
    consider(os:getenv("HECATE_SPARTAN_REBIRTH")).

consider(false) -> ok;
consider("")    -> ok;
consider(Token) -> rebirth_if_new(Token, hecate_spartan_service:data_dir()).

rebirth_if_new(Token, Dir) ->
    Marker = filename:join(Dir, ?MARKER),
    fire(read_marker(Marker) =:= Token, Token, Dir, Marker).

%% Same token already fired: this is an ordinary restart, keep the data.
fire(true, _Token, _Dir, _Marker) ->
    ok;
fire(false, Token, Dir, Marker) ->
    logger:notice("[spartan] REBIRTH '~ts': wiping ~ts for a clean slate", [Token, Dir]),
    _ = wipe(Dir),
    ok = filelib:ensure_dir(Marker),
    file:write_file(Marker, Token).

read_marker(Marker) ->
    case file:read_file(Marker) of
        {ok, Bin} -> binary_to_list(Bin);
        _Absent   -> undefined
    end.

%% Clear the directory's contents but not the directory itself (a bind mount).
wipe(Dir) ->
    rm_children(Dir, list_dir(Dir)).

rm_rf(Path) ->
    rm(filelib:is_dir(Path), Path).

rm(true, Path) ->
    rm_children(Path, list_dir(Path)),
    file:del_dir(Path);
rm(false, Path) ->
    file:delete(Path).

rm_children(Dir, Entries) ->
    lists:foreach(fun(E) -> rm_child(Dir, E) end, Entries).

rm_child(Dir, Entry) ->
    rm_rf(filename:join(Dir, Entry)).

list_dir(Path) ->
    case file:list_dir(Path) of
        {ok, Entries} -> Entries;
        _Err          -> []
    end.
