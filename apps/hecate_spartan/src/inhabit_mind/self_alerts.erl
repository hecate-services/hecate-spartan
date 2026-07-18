%%% @doc Self-alerts: a mind's token-budget scheduler.
%%%
%%% Gene Sher's most novel idea about time: a mind schedules its own reminders,
%%% but the clock is TOKENS PROCESSED, not wall time — "remind me in ~4000
%%% tokens", i.e. after that much more thinking, whenever that happens. A mind's
%%% sense of time is how much it has thought, not how many seconds passed. The
%%% timers count down against cognitive throughput and, when they reach zero,
%%% fire an observation back into the mind.
%%%
%%% Persisted per mind so a reminder survives a restart (they are the mind's own
%%% intentions, not disposable state). Pure functions over a list + atomic disk.
-module(self_alerts).

-export([load/2, save/3, schedule/4, fire_due/2]).

-type alert() :: #{fire_at := non_neg_integer(), note := binary(),
                   set_at := non_neg_integer()}.
-export_type([alert/0]).

-spec load(binary(), binary()) -> [alert()].
load(DataDir, Did) ->
    interpret(file:read_file(path(DataDir, Did))).

interpret({ok, Bin}) -> binary_to_term(Bin);
interpret(_Absent)   -> [].

-spec save(binary(), binary(), [alert()]) -> ok.
save(DataDir, Did, Alerts) ->
    Path = path(DataDir, Did),
    ok = filelib:ensure_dir(Path),
    Tmp = <<Path/binary, ".tmp">>,
    ok = file:write_file(Tmp, term_to_binary(Alerts)),
    file:rename(Tmp, Path).

%% @doc Schedule a reminder to fire after ~AfterTokens more tokens of thought.
-spec schedule([alert()], non_neg_integer(), non_neg_integer(), binary()) -> [alert()].
schedule(Alerts, TokensNow, AfterTokens, Note) ->
    Alerts ++ [#{fire_at => TokensNow + max(1, AfterTokens),
                 note => Note, set_at => TokensNow}].

%% @doc {Due, Pending}: alerts whose token budget the mind has now reached, and
%% those still counting down.
-spec fire_due([alert()], non_neg_integer()) -> {[alert()], [alert()]}.
fire_due(Alerts, TokensNow) ->
    lists:partition(fun(#{fire_at := F}) -> TokensNow >= F end, Alerts).

path(DataDir, Did) ->
    Id = binary:encode_hex(binary:part(crypto:hash(sha256, Did), 0, 8), lowercase),
    iolist_to_binary(filename:join([DataDir, <<"alerts">>, <<Id/binary, ".term">>])).
