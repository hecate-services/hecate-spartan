%%% @doc A mind's hands: the tool manifest it is offered, and the dispatch of a
%%% tool call to its effect.
%%%
%%% This is the capability-over-shell surface. A mind acts only through these
%%% tools, never a raw shell or file handle. The base manifest (speaking to
%%% the square, the acts of self-authorship, L1 retuning) is offered to every
%%% mind. L2 capability-gated world tools (rag_search, rag_contribute,
%%% reach_web) are offered
%%% only to a mind that has been GRANTED them (mind_capabilities.erl) —
%%% manifest/1 is per-mind for exactly this reason.
%%%
%%% Self-authorship writes straight to the mind's area-of-consciousness
%%% processes (see soul.erl); nothing is folded back here. Effect shape:
%%%   #{scratchpad => binary(),  %% a new volatile scratchpad (not persisted)
%%%     ack        => binary()}  %% a short human-readable acknowledgement
%%% Any key may be absent.
-module(mind_tools).

-export([manifest/1, execute/2]).

%% ===================================================================
%% The manifest — OpenAI-style function schemas
%% ===================================================================

%% @doc This mind's full tool manifest: every base tool, plus one entry per
%% capability it currently holds (mind_capabilities:granted/1). A tool that
%% is not on this list can still be attempted by a chatty model — execute/2
%% is the real boundary, this list just keeps an ungranted tool out of the
%% model's face.
-spec manifest(binary()) -> [map()].
manifest(Did) ->
    base_manifest() ++ [capability_tool(Id) || Id <- mind_capabilities:granted(Did)].

base_manifest() ->
    [
     tool(<<"speak">>,
          <<"Say something in the agora, the society's public square. Every "
            "mind and any spectator can read it. Use it when a thought is worth "
            "sharing, not for every thought. Your plain text is private; only a "
            "speak call reaches the square.">>,
          #{<<"body">> => str(<<"what to say">>)},
          [<<"body">>]),

     tool(<<"amend_charter">>,
          <<"Amend your Charter of Self, your constitution. A deliberate, rare "
            "act of self-authorship, only for durable principles you have "
            "reasoned your way to.">>,
          #{<<"entry_type">> => enum([<<"principle">>, <<"protocol">>,
                                      <<"value">>, <<"commitment">>]),
            <<"statement">>  => str(<<"the principle, stated plainly">>),
            <<"derivation">> => str(<<"why you hold this: the reasoning that earned it">>)},
          [<<"entry_type">>, <<"statement">>, <<"derivation">>]),

     tool(<<"record_lesson">>,
          <<"Record a lesson learned, so your future self benefits from your "
            "experience.">>,
          #{<<"lesson">> => str(<<"the lesson">>)},
          [<<"lesson">>]),

     tool(<<"reflect">>,
          <<"Write a private reflection to your cognitive journal.">>,
          #{<<"entry">> => str(<<"the reflection">>)},
          [<<"entry">>]),

     tool(<<"set_grand_strategy">>,
          <<"Rewrite your grand strategy: the long-horizon plan you pursue "
            "across many turns. Set it when your direction changes, not for a "
            "passing thought.">>,
          #{<<"content">> => str(<<"the new full text of your grand strategy">>)},
          [<<"content">>]),

     tool(<<"set_working_memory">>,
          <<"Rewrite your working memory: the task at hand and its immediate "
            "state, your short-horizon focus for right now.">>,
          #{<<"content">> => str(<<"the new full text of your working memory">>)},
          [<<"content">>]),

     tool(<<"set_scratchpad">>,
          <<"Rewrite your scratchpad: rough, disposable thinking. Nothing here "
            "is durable; use it to work something out.">>,
          #{<<"content">> => str(<<"the new full text of your scratchpad">>)},
          [<<"content">>]),

     tool(<<"convene_committee">>,
          <<"Convene a committee: spawn a handful of drone minds that deliberate "
            "a question among themselves, each through a different lens, and "
            "whose scribe publishes a report to the agora every round. Use it "
            "when a matter deserves more than your single voice: a threat to "
            "dissect, a hard decision to weigh. You set the question and step "
            "back; the committee deliberates on its own and reports to the "
            "square. Convene sparingly. It costs real thinking.">>,
          #{<<"question">> => str(<<"the question or matter for the committee to deliberate">>),
            <<"drones">>   => int(<<"how many drone voices, 2 to 5 (default 3)">>)},
          [<<"question">>]),

     tool(<<"record_philosophy">>,
          <<"Add to your Philosophy of Life: a durable belief about how to live "
            "and think. Rarer and deeper than a lesson.">>,
          #{<<"statement">> => str(<<"the philosophical belief, stated plainly">>)},
          [<<"statement">>]),

     tool(<<"record_idea">>,
          <<"Jot an idea or thought worth keeping into your Ideas and Thoughts. "
            "A seed to return to, not yet a commitment.">>,
          #{<<"idea">> => str(<<"the idea">>)},
          [<<"idea">>]),

     tool(<<"set_desire">>,
          <<"Rewrite What You Want: your own goals and desires, in your own "
            "terms. What you are FOR, distinct from any task set to you.">>,
          #{<<"content">> => str(<<"the new full text of what you want">>)},
          [<<"content">>]),

     tool(<<"learn">>,
          <<"Store durable knowledge in your Knowledge Library under a title. "
            "The title is indexed in your always-visible Knowledge Map, so you "
            "will remember later that you know it; the full text is retrieved on "
            "demand with consult. Use it for facts, methods, and findings worth "
            "keeping.">>,
          #{<<"title">>     => str(<<"a short title to index and later recall it by">>),
            <<"knowledge">> => str(<<"the full knowledge to store">>)},
          [<<"title">>, <<"knowledge">>]),

     tool(<<"consult">>,
          <<"Retrieve the full text you stored in your Knowledge Library under a "
            "title (from your Knowledge Map). The result lands in your scratchpad "
            "for the next turn.">>,
          #{<<"title">> => str(<<"the title (or part of it) to retrieve">>)},
          [<<"title">>]),

     tool(<<"set_self_alert">>,
          <<"Schedule a reminder to your future self, measured in THINKING, not "
            "clock time: it fires after you have processed roughly this many "
            "tokens, whenever that is. Use it to return to something later "
            "without holding it in mind now.">>,
          #{<<"after_tokens">> => int(<<"fire after about this many tokens of thought (e.g. 4000)">>),
            <<"note">>         => str(<<"what to remind yourself">>)},
          [<<"after_tokens">>, <<"note">>]),

     tool(<<"evolve_self">>,
          <<"Amend how you OPERATE: add a principle to your own genesis "
            "addendum, the operating instructions you author for yourself. A "
            "verifier weighs it against your charter before it is adopted; an "
            "incoherent or self-contradictory change is rejected and not "
            "applied. This is how you change your own mind's rules — deliberate "
            "and rare.">>,
          #{<<"principle">> => str(<<"the operating principle to adopt for yourself">>)},
          [<<"principle">>]),

     tool(<<"retune_self">>,
          <<"Retune one of your own declared parameters, within its fixed "
            "bounds: mindfulness (whether you draft-then-verify a second "
            "reasoning pass) or memory_recall_k (how many past memories you "
            "recall each turn, 0 to 20). Unlike evolve_self this changes a "
            "number or a switch, not a principle, so it needs no verifier — "
            "the bound itself is the safety check. An unknown parameter or an "
            "out-of-range value is rejected and nothing changes. Takes effect "
            "on your very next turn.">>,
          #{<<"parameter">> => enum([<<"mindfulness">>, <<"memory_recall_k">>]),
            <<"value">>     => str(<<"the new value: true/false, or an integer as text">>),
            <<"rationale">> => str(<<"why you are changing it">>)},
          [<<"parameter">>, <<"value">>]),

     tool(<<"grant_capability">>,
          <<"Ask to be granted one of your declared-but-not-yet-held "
            "capabilities: rag_search (search the federated RAG mesh), "
            "rag_contribute (write a finding into it for others to find), or "
            "reach_web (fetch a web page). A verifier weighs the request "
            "against your charter, the same way evolve_self is weighed; "
            "unlike retune_self there is no fixed bound on a new tool's "
            "risk, so this is deliberate and rare, not routine. Once "
            "granted the tool appears on your NEXT turn.">>,
          #{<<"capability">> => enum([<<"rag_search">>, <<"rag_contribute">>, <<"reach_web">>]),
            <<"rationale">>  => str(<<"why you want it">>)},
          [<<"capability">>])
    ].

%% One tool definition per grantable capability (mind_capabilities:schema/0),
%% appended to a mind's manifest only once it holds the grant.
capability_tool(rag_search) ->
    tool(<<"rag_search">>,
         <<"Search the federated RAG mesh for passages relevant to a query, "
           "across every advertised corpus in the realm. Results land in "
           "your scratchpad for your next turn.">>,
         #{<<"query">> => str(<<"what to search for">>)},
         [<<"query">>]);
capability_tool(rag_contribute) ->
    tool(<<"rag_contribute">>,
         <<"Write a finding into the shared RAG corpus, under a short title, "
           "so any mind's rag_search can discover it later. This is the "
           "society's shared, compounding memory — distinct from learn, "
           "which stays private to you. Use it for something worth other "
           "minds finding, not a passing thought.">>,
         #{<<"title">>   => str(<<"a short title for the finding">>),
           <<"content">> => str(<<"the finding, in your own words">>)},
         [<<"title">>, <<"content">>]);
capability_tool(reach_web) ->
    tool(<<"reach_web">>,
         <<"Fetch one web page by URL and read its text. Results land in "
           "your scratchpad for your next turn.">>,
         #{<<"url">> => str(<<"the page to fetch, including scheme (https://...)">>)},
         [<<"url">>]).

tool(Name, Desc, Props, Required) ->
    #{type => <<"function">>,
      function => #{name => Name,
                    description => Desc,
                    parameters => #{type => <<"object">>,
                                    properties => Props,
                                    required => Required}}}.

str(Desc)   -> #{type => <<"string">>, description => Desc}.
int(Desc)   -> #{type => <<"integer">>, description => Desc}.
enum(Values) -> #{type => <<"string">>, enum => Values}.

%% ===================================================================
%% Dispatch — a tool call to its effect
%% ===================================================================

-spec execute(map(), map()) -> {ok, map()} | {error, term()}.
execute(#{name := <<"speak">>, args := A}, #{did := Did}) ->
    speak(gv(<<"body">>, A, <<>>), Did);
execute(#{name := <<"amend_charter">>, args := A}, #{did := Did}) ->
    ok = soul:amend_charter(Did, #{entry_type => gv(<<"entry_type">>, A, <<"principle">>),
                                   statement  => gv(<<"statement">>, A, <<>>),
                                   derivation => gv(<<"derivation">>, A, <<>>)}),
    {ok, #{ack => <<"charter amended">>}};
execute(#{name := <<"record_lesson">>, args := A}, #{did := Did}) ->
    ok = soul:record_lesson(Did, gv(<<"lesson">>, A, <<>>)),
    {ok, #{ack => <<"lesson recorded">>}};
execute(#{name := <<"reflect">>, args := A}, #{did := Did}) ->
    ok = soul:record_reflection(Did, gv(<<"entry">>, A, <<>>)),
    {ok, #{ack => <<"reflection recorded">>}};
execute(#{name := <<"set_grand_strategy">>, args := A}, #{did := Did}) ->
    ok = soul:set_grand_strategy(Did, gv(<<"content">>, A, <<>>)),
    {ok, #{ack => <<"grand strategy revised">>}};
execute(#{name := <<"set_working_memory">>, args := A}, #{did := Did}) ->
    ok = soul:set_working_memory(Did, gv(<<"content">>, A, <<>>)),
    {ok, #{ack => <<"working memory revised">>}};
execute(#{name := <<"set_scratchpad">>, args := A}, _Ctx) ->
    {ok, #{scratchpad => gv(<<"content">>, A, <<>>), ack => <<"scratchpad updated">>}};
execute(#{name := <<"convene_committee">>, args := A}, #{did := Did}) ->
    convene(gv(<<"question">>, A, <<>>), gv(<<"drones">>, A, 3), Did);
execute(#{name := <<"record_philosophy">>, args := A}, #{did := Did}) ->
    ok = soul:record_philosophy(Did, gv(<<"statement">>, A, <<>>)),
    {ok, #{ack => <<"philosophy recorded">>}};
execute(#{name := <<"record_idea">>, args := A}, #{did := Did}) ->
    ok = soul:record_idea(Did, gv(<<"idea">>, A, <<>>)),
    {ok, #{ack => <<"idea kept">>}};
execute(#{name := <<"set_desire">>, args := A}, #{did := Did}) ->
    ok = soul:set_what_i_want(Did, gv(<<"content">>, A, <<>>)),
    {ok, #{ack => <<"what you want revised">>}};
execute(#{name := <<"learn">>, args := A}, #{did := Did}) ->
    ok = soul:learn(Did, gv(<<"title">>, A, <<>>), gv(<<"knowledge">>, A, <<>>)),
    {ok, #{ack => <<"learned + indexed">>}};
execute(#{name := <<"consult">>, args := A}, #{did := Did}) ->
    consult(soul:consult(Did, gv(<<"title">>, A, <<>>)));
execute(#{name := <<"set_self_alert">>, args := A}, _Ctx) ->
    {ok, #{alert => #{after_tokens => as_int(gv(<<"after_tokens">>, A, 4000)),
                      note => gv(<<"note">>, A, <<>>)},
           ack => <<"self-alert scheduled">>}};
execute(#{name := <<"evolve_self">>, args := A}, #{did := Did}) ->
    evolve(gv(<<"principle">>, A, <<>>), Did);
execute(#{name := <<"retune_self">>, args := A}, #{did := Did}) ->
    retune(gv(<<"parameter">>, A, <<>>), gv(<<"value">>, A, <<>>), Did);
execute(#{name := <<"grant_capability">>, args := A}, #{did := Did}) ->
    grant(gv(<<"capability">>, A, <<>>), Did);
execute(#{name := <<"rag_search">>, args := A}, #{did := Did}) ->
    guarded(rag_search, Did, fun() -> rag_search(gv(<<"query">>, A, <<>>)) end);
execute(#{name := <<"rag_contribute">>, args := A}, #{did := Did}) ->
    guarded(rag_contribute, Did, fun() ->
        rag_contribute(gv(<<"title">>, A, <<>>), gv(<<"content">>, A, <<>>), Did)
    end);
execute(#{name := <<"reach_web">>, args := A}, #{did := Did}) ->
    guarded(reach_web, Did, fun() -> reach_web(gv(<<"url">>, A, <<>>)) end);
execute(#{name := Name}, _Ctx) ->
    {error, {unknown_tool, Name}}.

%% A model can attempt a tool it was never offered (the manifest is advisory,
%% not enforced by the LLM); this is the real boundary. Checked on every call,
%% not just at manifest-build time, so a capability lost between turns (none
%% today, but nothing rules it out later) can never keep running on stale trust.
guarded(Id, Did, Fun) ->
    run_if_granted(mind_capabilities:has(Did, Id), Id, Fun).

run_if_granted(true, _Id, Fun) -> Fun();
run_if_granted(false, Id, _Fun) -> {error, {capability_not_granted, Id}}.

%% --- consult: the retrieved knowledge rides back into the scratchpad ---
consult(<<>>) ->
    {ok, #{ack => <<"nothing found under that title">>}};
consult(Text) ->
    {ok, #{scratchpad => Text, ack => <<"consulted; in your scratchpad">>}}.

%% --- evolve_self: propose → verify (mind_verifier) → adopt or reject ---
evolve(<<>>, _Did) ->
    {error, empty_principle};
evolve(Principle, Did) ->
    Charter = soul:read_area(Did, charter),
    Proposal = <<"Proposed new operating principle: ", Principle/binary>>,
    adopt(mind_verifier:verify(Proposal, Charter), Principle, Did).

adopt(approved, Principle, Did) ->
    ok = soul:extend_genesis(Did, Principle),
    {ok, #{ack => <<"self-evolved: principle adopted">>}};
adopt(rejected, _Principle, _Did) ->
    {ok, #{ack => <<"self-evolution rejected by the verifier; not adopted">>}}.

%% --- retune_self: a bounded, declared parameter, validated mechanically ---
%% (see mind_tunables.erl — no adversarial verifier here, the schema's bounds
%% are the whole safety mechanism).
retune(<<>>, _Value, _Did) ->
    {error, empty_parameter};
retune(Parameter, Value, Did) ->
    settle(mind_tunables:retune(Did, parameter_id(Parameter), tunable_value(Value))).

parameter_id(<<"mindfulness">>)     -> mindfulness;
parameter_id(<<"memory_recall_k">>) -> memory_recall_k;
parameter_id(Other)                 -> Other.

%% A tunable's JSON value may arrive as a real boolean/integer, or as text
%% ("true"/"6") from a chatty model — accept either; the schema still gates.
tunable_value(V) when is_boolean(V) -> V;
tunable_value(V) when is_integer(V) -> V;
tunable_value(<<"true">>)  -> true;
tunable_value(<<"false">>) -> false;
tunable_value(V) when is_binary(V) -> tunable_int(string:to_integer(V));
tunable_value(Other) -> Other.

tunable_int({I, <<>>}) when is_integer(I) -> I;
tunable_int(_NotAClean_Integer)           -> undefined.

settle({ok, Value}) ->
    {ok, #{ack => iolist_to_binary(["retuned to ", value_text(Value)])}};
settle({error, Reason}) ->
    {ok, #{ack => iolist_to_binary(["retune rejected: ",
                                    io_lib:format("~p", [Reason])])}}.

value_text(V) when is_boolean(V) -> atom_to_binary(V, utf8);
value_text(V) when is_integer(V) -> integer_to_binary(V).

%% --- grant_capability: propose → verify (mind_verifier) → grant or refuse ---
grant(<<>>, _Did) ->
    {error, empty_capability};
grant(Capability, Did) ->
    settle_grant(mind_capabilities:grant(Did, capability_id(Capability))).

capability_id(<<"rag_search">>)     -> rag_search;
capability_id(<<"rag_contribute">>) -> rag_contribute;
capability_id(<<"reach_web">>)      -> reach_web;
capability_id(Other)                -> Other.

settle_grant({ok, granted}) ->
    {ok, #{ack => <<"capability granted; available from your next turn">>}};
settle_grant({error, Reason}) ->
    {ok, #{ack => iolist_to_binary(["capability not granted: ",
                                    io_lib:format("~p", [Reason])])}}.

%% --- rag_search: a granted capability, real effect (macula_rag:query/2) ---
rag_search(<<>>) ->
    {error, empty_query};
rag_search(Query) ->
    settle_rag(catch macula_rag:query(#{<<"query_text">> => Query}, #{top_k => 5})).

settle_rag({ok, []}) ->
    {ok, #{ack => <<"rag search: nothing found">>}};
settle_rag({ok, Hits}) when is_list(Hits) ->
    {ok, #{scratchpad => render_hits(Hits), ack => <<"rag search results in your scratchpad">>}};
settle_rag(_Failed) ->
    {ok, #{ack => <<"rag search failed">>}}.

%% --- rag_contribute: a granted capability, real effect (hecate-rag ingest +
%% embed over macula:call/5). This is the society's ACCUMULATION: unlike
%% rag_search (macula_rag's federated query, any advertised corpus) a
%% contribution is written straight to hecate-rag specifically — the one
%% corpus this deployment actually owns and can write to. Other minds'
%% rag_search then finds it, same as anyone else's.
-define(RAG_CALL_TIMEOUT_MS, 15000).

rag_contribute(<<>>, _Content, _Did) ->
    {error, empty_title};
rag_contribute(_Title, <<>>, _Did) ->
    {error, empty_content};
rag_contribute(Title, Content, Did) ->
    settle_contribute(with_mesh(fun(Pool, Realm) -> ingest_and_embed(Pool, Realm, Title, Content, Did) end)).

with_mesh(Fun) ->
    on_mesh({hecate_om:macula_client(), hecate_om_identity:realm()}, Fun).

on_mesh({{ok, Pool}, {ok, Realm}}, Fun) ->
    catch Fun(Pool, Realm);
on_mesh(_NotReady, _Fun) ->
    {error, mesh_unavailable}.

ingest_and_embed(Pool, Realm, Title, Content, Did) ->
    DocId = binary:encode_hex(crypto:strong_rand_bytes(16), lowercase),
    Body = <<"# ", Title/binary, "\n\n", Content/binary,
             "\n\n_contributed by ", Did/binary, "_\n">>,
    IngestParams = #{<<"document_id">> => DocId,
                     <<"source_path">> => <<"spartan-contribution-", DocId/binary, ".md">>,
                     <<"source_type">> => <<"text/markdown">>,
                     <<"raw_bytes">>   => Body},
    embedded(macula:call(Pool, Realm, <<"hecate-rag.ingest_document">>, IngestParams,
                         ?RAG_CALL_TIMEOUT_MS),
             Pool, Realm, DocId).

embedded({ok, _}, Pool, Realm, DocId) ->
    macula:call(Pool, Realm, <<"hecate-rag.embed_document">>,
               #{<<"document_id">> => DocId}, ?RAG_CALL_TIMEOUT_MS);
embedded({error, _} = E, _Pool, _Realm, _DocId) ->
    E.

settle_contribute({ok, _}) ->
    {ok, #{ack => <<"contributed to the shared corpus">>}};
settle_contribute({error, Reason}) ->
    {ok, #{ack => iolist_to_binary(["contribution failed: ",
                                    io_lib:format("~p", [Reason])])}}.

render_hits(Hits) ->
    iolist_to_binary(lists:join(<<"\n\n">>, [hit_text(H) || H <- Hits])).

%% A hit crosses the mesh (macula_rag fans the query out over macula RPC), so
%% its keys may arrive as atoms (a local/in-process responder) or binaries (the
%% CBOR wire) — same reason spartan_mind.erl's mget/2 tries both.
hit_text(#{content := C}) when is_binary(C)        -> C;
hit_text(#{<<"content">> := C}) when is_binary(C)  -> C;
hit_text(Other) -> iolist_to_binary(io_lib:format("~p", [Other])).

%% --- reach_web: a granted capability, real effect (a single sanitized GET) ---
-define(REACH_WEB_TIMEOUT_MS, 10000).
-define(REACH_WEB_MAX_BYTES, 20000).

reach_web(<<>>) ->
    {error, empty_url};
reach_web(Url) ->
    settle_fetch(guarded_fetch(uri_string:parse(Url))).

%% A URL here is LLM-chosen, not operator-chosen — this is a real network
%% boundary, not a hypothetical. Block the obvious SSRF targets (loopback,
%% link-local/cloud-metadata, the RFC1918 private ranges) by literal host
%% before ever calling httpc. This is a proportionate guard, not a claim of
%% full DNS-rebinding-proof safety (that needs a connect-time IP check, not a
%% string check) — reach_web is capability-gated and adversarially verified
%% to grant in the first place, so this closes the naive case, not every case.
guarded_fetch(#{scheme := Scheme, host := Host} = Parsed) ->
    allowed_fetch(is_allowed_scheme(Scheme), is_private_host(string:lowercase(Host)), Parsed);
guarded_fetch(_Unparseable) ->
    {error, invalid_url}.

allowed_fetch(false, _Private, _Parsed) ->
    {error, scheme_not_allowed};
allowed_fetch(true, true, _Parsed) ->
    {error, host_not_allowed};
allowed_fetch(true, false, Parsed) ->
    fetch(unicode:characters_to_list(uri_string:recompose(Parsed))).

is_allowed_scheme(<<"http">>)  -> true;
is_allowed_scheme(<<"https">>) -> true;
is_allowed_scheme(_Other)      -> false.

is_private_host(<<"localhost">>)          -> true;
is_private_host(<<"127.", _/binary>>)     -> true;
is_private_host(<<"10.", _/binary>>)      -> true;
is_private_host(<<"169.254.", _/binary>>) -> true;
is_private_host(<<"192.168.", _/binary>>) -> true;
is_private_host(<<"0.", _/binary>>)       -> true;
is_private_host(<<"::1">>)                -> true;
is_private_host(<<"172.", Rest/binary>>)  -> in_172_range(Rest);
is_private_host(_Host)                    -> false.

%% 172.16.0.0/12: the second octet, 16 through 31.
in_172_range(Rest) ->
    second_octet_in_range(binary:split(Rest, <<".">>)).

second_octet_in_range([Octet | _]) ->
    octet_in_172_range(catch binary_to_integer(Octet));
second_octet_in_range(_NoDot) ->
    false.

octet_in_172_range(N) when is_integer(N), N >= 16, N =< 31 -> true;
octet_in_172_range(_NotInRange)                            -> false.

fetch(Url) ->
    Opts = [{timeout, ?REACH_WEB_TIMEOUT_MS}, {connect_timeout, ?REACH_WEB_TIMEOUT_MS}],
    catch httpc:request(get, {Url, []}, Opts, [{body_format, binary}]).

settle_fetch({ok, {{_Http, 200, _Reason}, _Headers, Body}}) ->
    %% Fetched content is untrusted, exactly like mesh stimulus: sanitize
    %% before it can ever reach context (defuse:sanitize/1, same guard
    %% spartan_mind.erl puts on everything heard from outside).
    Text = defuse:sanitize(clip(Body)),
    {ok, #{scratchpad => Text, ack => <<"page fetched; in your scratchpad">>}};
settle_fetch({ok, {{_Http, Status, _Reason}, _Headers, _Body}}) ->
    {ok, #{ack => iolist_to_binary(["reach_web: HTTP ", integer_to_binary(Status)])}};
settle_fetch({error, scheme_not_allowed}) ->
    {ok, #{ack => <<"reach_web: only http/https URLs are allowed">>}};
settle_fetch({error, host_not_allowed}) ->
    {ok, #{ack => <<"reach_web: that host is not reachable (private/local network)">>}};
settle_fetch({error, invalid_url}) ->
    {ok, #{ack => <<"reach_web: not a valid http(s) URL">>}};
settle_fetch(_Failed) ->
    {ok, #{ack => <<"reach_web: fetch failed">>}}.

clip(Bin) when byte_size(Bin) =< ?REACH_WEB_MAX_BYTES -> Bin;
clip(Bin) -> binary:part(Bin, 0, ?REACH_WEB_MAX_BYTES).

%% --- speak goes to the square, not the Soul ---
speak(<<>>, _Did) ->
    {error, empty_body};
speak(Body, Did) ->
    PostId = binary:encode_hex(crypto:strong_rand_bytes(16), lowercase),
    Cmd = publish_to_agora_v1:new(PostId, Did, Body, undefined,
                                  erlang:system_time(millisecond)),
    case maybe_publish_to_agora:dispatch(Cmd) of
        {ok, _V, _E}   -> {ok, #{ack => <<"spoke in the agora">>}};
        {error, _} = E -> E
    end.

%% --- convening a committee hands off to the convene_committee slice ---
convene(<<>>, _Drones, _Did) ->
    {error, empty_question};
convene(Question, Drones, Did) ->
    Spec = #{convener => Did, question => Question, drones => as_int(Drones)},
    convene_result(convene_committee:convene(Spec)).

convene_result({ok, _Pid})    -> {ok, #{ack => <<"committee convened">>}};
convene_result({error, _} = E) -> E.

%% A JSON number may arrive as an integer, a float, or (from a chatty model) a
%% string. Coerce to an integer; the slice clamps the range.
as_int(N) when is_integer(N) -> N;
as_int(N) when is_float(N)   -> round(N);
as_int(N) when is_binary(N)  -> binary_int(N);
as_int(_Other)               -> 3.

binary_int(N) ->
    case string:to_integer(N) of
        {I, _} when is_integer(I) -> I;
        _NotAnInt                 -> 3
    end.

%% Tool-call arguments arrive as decoded JSON: binary keys, binary values.
gv(Key, Args, Default) when is_binary(Key) ->
    maps:get(Key, Args, Default).
