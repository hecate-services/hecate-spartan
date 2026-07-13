%%% @doc Service identity + UCAN issuance for hecate-spartan.
%%%
%%% Owns the service's own Ed25519 keypair (its issuer identity). On boot it
%%% loads the keypair from the state dir, or generates and persists one. From
%%% it we derive the service DID, mint per-entity UCANs, and verify UCANs
%%% presented on requests.
%%%
%%% Entities are self-sovereign: each holds its own Ed25519 keypair and DID.
%%% We never see an entity's secret. Registration proves DID possession via a
%%% signature over a challenge; thereafter the entity carries the UCAN we mint
%%% here (bearer, verified against our issuer key + capability set).
-module(hecate_spartan_identity).
-behaviour(gen_server).

-export([start_link/0,
         service_did/0,
         mint_entity_ucan/2,
         verify_ucan/1,
         verify_entity_sig/3,
         registration_challenge/2,
         entity_caps/2]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% UCAN lifetime: 30 days. Entities re-register (cheap) to refresh.
-define(UCAN_TTL_SECONDS, 2592000).
-define(DID_KEY, {?MODULE, did}).
-define(PUBKEY_KEY, {?MODULE, pubkey}).

-record(st, {did :: binary(), pubkey :: binary(), privkey :: binary()}).

%% ===================================================================
%% API
%% ===================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc This service's issuer DID (derived from its public key).
-spec service_did() -> binary().
service_did() ->
    persistent_term:get(?DID_KEY).

%% @doc Mint a UCAN for a registered entity, scoping it to its realm topics.
-spec mint_entity_ucan(EntityDid :: binary(), Realm :: binary()) ->
    {ok, binary()} | {error, term()}.
mint_entity_ucan(EntityDid, Realm) ->
    gen_server:call(?MODULE, {mint, EntityDid, Realm}).

%% @doc Verify a presented UCAN against our issuer public key. Checks
%% signature, expiry, and not-before; returns the decoded payload.
-spec verify_ucan(Token :: binary()) -> {ok, map()} | {error, term()}.
verify_ucan(Token) ->
    macula_ucan_nif:verify(Token, persistent_term:get(?PUBKEY_KEY)).

%% @doc Verify an entity's Ed25519 signature over a message (proof of DID
%% possession at registration).
-spec verify_entity_sig(Message :: binary(), Signature :: binary(),
                        PubKey :: binary()) -> boolean().
verify_entity_sig(Message, Signature, PubKey) ->
    macula_crypto_nif:verify(Message, Signature, PubKey).

%% @doc The canonical message an entity must sign to prove it holds the
%% private key behind its DID. Bound to the DID and a client timestamp.
-spec registration_challenge(Did :: binary(), TsBin :: binary()) -> binary().
registration_challenge(Did, TsBin) ->
    <<"hecate-spartan:register:", Did/binary, ":", TsBin/binary>>.

%% @doc The capabilities an entity's UCAN grants: send to any inbox, receive
%% on its own inbox, broadcast, share content, and speak and listen in the
%% agora — all realm-scoped.
%%
%% `agora/post' is a separate capability from `msg/send' on purpose. Sending is
%% correspondence; posting is public speech that leaves the commons as a
%% body-bearing fact anyone may render. They are different powers, so an
%% operator can grant one without the other.
-spec entity_caps(Realm :: binary(), EntityDid :: binary()) -> [map()].
entity_caps(Realm, EntityDid) ->
    [ #{with => <<"spartan/", Realm/binary, "/inbox/">>,
        can => <<"msg/send">>},
      #{with => <<"spartan/", Realm/binary, "/inbox/", EntityDid/binary>>,
        can => <<"msg/recv">>},
      #{with => <<"spartan/", Realm/binary, "/broadcast">>,
        can => <<"msg/send">>},
      #{with => <<"spartan/", Realm/binary, "/artifact">>,
        can => <<"content/share">>},
      #{with => <<"spartan/", Realm/binary, "/agora">>,
        can => <<"agora/post">>},
      #{with => <<"spartan/", Realm/binary, "/agora">>,
        can => <<"agora/read">>} ].

%% ===================================================================
%% gen_server
%% ===================================================================

init([]) ->
    {Pub, Priv} = load_or_generate(key_dir()),
    Did = did_from_pubkey(Pub),
    persistent_term:put(?DID_KEY, Did),
    persistent_term:put(?PUBKEY_KEY, Pub),
    logger:info("hecate_spartan_identity ready, service DID ~s", [Did]),
    {ok, #st{did = Did, pubkey = Pub, privkey = Priv}}.

handle_call({mint, EntityDid, Realm}, _From,
            #st{did = Did, privkey = Priv} = St) ->
    Caps = entity_caps(Realm, EntityDid),
    Exp = erlang:system_time(second) + ?UCAN_TTL_SECONDS,
    Reply = macula_ucan_nif:create(Did, EntityDid, Caps, Priv, #{exp => Exp}),
    {reply, Reply, St};
handle_call(_Req, _From, St) ->
    {reply, {error, unknown_request}, St}.

handle_cast(_Msg, St) -> {noreply, St}.
handle_info(_Info, St) -> {noreply, St}.
terminate(_Reason, _St) -> ok.
code_change(_Old, St, _Extra) -> {ok, St}.

%% ===================================================================
%% Internal
%% ===================================================================

key_dir() ->
    {ok, Dir} = application:get_env(hecate_spartan, data_dir),
    Dir.

%% Load the raw 32-byte Ed25519 keypair from disk, or generate + persist one.
%% We store raw keys (not a wrapped identity file) so the bytes are exactly
%% what macula_crypto_nif:sign/verify and macula_ucan_nif expect.
load_or_generate(Dir) ->
    PrivPath = filename:join(Dir, "service_ed25519.key"),
    PubPath = filename:join(Dir, "service_ed25519.pub"),
    case {file:read_file(PrivPath), file:read_file(PubPath)} of
        {{ok, Priv}, {ok, Pub}} ->
            {Pub, Priv};
        _ ->
            {ok, {Pub, Priv}} = macula_crypto_nif:generate_keypair(),
            ok = filelib:ensure_dir(PrivPath),
            ok = file:write_file(PrivPath, Priv),
            ok = file:change_mode(PrivPath, 8#600),
            ok = file:write_file(PubPath, Pub),
            {Pub, Priv}
    end.

did_from_pubkey(Pub) ->
    <<"did:macula:spartan:", (binary:encode_hex(Pub))/binary>>.
