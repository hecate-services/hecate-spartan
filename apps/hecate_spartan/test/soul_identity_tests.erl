%%% @doc DEFECT 8, the sticky torn identity.
%%%
%%% `soul.erl' wrote the identity file with a bare `file:write_file' while its
%%% sibling `soul_area' has `write_atomic', and the read branch accepted ANY
%%% existing file with no validation. So a file torn at birth was adopted as the
%%% mind's identity forever: re-birth never fired, because the file existed. The
%%% window is one write, at birth, holding the DID, name, genesis version and
%%% founding brief.
-module(soul_identity_tests).

-include_lib("eunit/include/eunit.hrl").

identity_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [fun a_whole_identity_is_reused/1,
      fun a_torn_identity_is_not_adopted/1,
      fun an_unreadable_identity_does_not_crash_boot/1,
      fun no_temp_file_is_left_behind/1]}.

setup() ->
    Dir = iolist_to_binary(filename:join(
        ["/tmp", "spartan_identity_test",
         integer_to_list(erlang:unique_integer([positive]))])),
    _ = os:cmd("rm -rf " ++ binary_to_list(Dir)),
    Dir.

cleanup(Dir) ->
    _ = os:cmd("rm -rf " ++ binary_to_list(Dir)),
    ok.

did() ->
    <<"did:test:", (integer_to_binary(erlang:unique_integer([positive])))/binary>>.

birth() ->
    #{name => <<"tester">>, genesis_version => <<"test">>,
      founding_brief => <<"a mind for testing">>}.

path(Dir, Did) ->
    iolist_to_binary(filename:join(soul:dir(Dir, Did), <<"identity">>)).

%% Birth is idempotent: a good file is read, never overwritten.
a_whole_identity_is_reused(Dir) ->
    fun() ->
        Did = did(),
        {ok, First} = soul:open(Did, Dir, birth()),
        {ok, Again} = soul:open(Did, Dir, birth()),
        ?assertEqual(maps:get(born_at, First), maps:get(born_at, Again)),
        ?assertEqual(<<"tester">>, maps:get(name, Again))
    end.

%% The defect: a partial file used to be adopted, yielding a mind whose name was
%% `undefined' forever.
a_torn_identity_is_not_adopted(Dir) ->
    fun() ->
        Did = did(),
        {ok, _} = soul:open(Did, Dir, birth()),
        Path = path(Dir, Did),
        {ok, Bin} = file:read_file(Path),
        ok = file:write_file(Path, binary:part(Bin, 0, 12)),
        {ok, Reborn} = soul:open(Did, Dir, birth()),
        ?assertEqual(<<"tester">>, maps:get(name, Reborn)),
        ?assertEqual(Did, maps:get(did, Reborn))
    end.

%% A torn file can also make base64 or integer decoding throw, which would take
%% the mind's boot down rather than re-birth it.
an_unreadable_identity_does_not_crash_boot(Dir) ->
    fun() ->
        Did = did(),
        {ok, _} = soul:open(Did, Dir, birth()),
        ok = file:write_file(path(Dir, Did),
                             <<"did=x\nname=y\nborn_at=not-a-number\nfounding_brief_b64=!!!\n">>),
        ?assertMatch({ok, #{name := <<"tester">>}}, soul:open(Did, Dir, birth()))
    end.

no_temp_file_is_left_behind(Dir) ->
    fun() ->
        Did = did(),
        {ok, _} = soul:open(Did, Dir, birth()),
        ?assertEqual({error, enoent},
                     file:read_file(<<(path(Dir, Did))/binary, ".tmp">>))
    end.
