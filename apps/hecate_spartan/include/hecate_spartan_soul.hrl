-ifndef(HECATE_SPARTAN_SOUL_HRL).
-define(HECATE_SPARTAN_SOUL_HRL, true).

%% Soul aggregate status — bit flags (powers of 2), manipulated via
%% evoq_bit_flags. Status is an integer, never an atom.
-define(SOUL_BORN, 1).   %% 2^0

%% The durable self. Rebuilt from the soul-<hash(did)> stream on boot,
%% one event per act of self-authorship. Scratchpad is deliberately NOT
%% here: it is disposable by its own contract and lives in volatile
%% process state, lost on restart. Everything in this record is something
%% the mind would be sad to lose.
-record(soul, {
    did             :: binary() | undefined,   %% public identity, set at birth
    name            :: binary() | undefined,
    genesis_version :: binary() | undefined,   %% which L1 suit it was born into
    founding_brief  :: binary() | undefined,   %% why this mind exists: context, not command
    born_at         :: integer() | undefined,
    charter    = [] :: [map()],                 %% principle | protocol | value | commitment
    lessons    = [] :: [map()],
    journal    = [] :: [map()],
    grand_strategy  :: binary() | undefined,
    working_memory  :: binary() | undefined,
    backend         :: binary() | undefined,    %% the chosen model id (decoupled identity)
    status     = 0  :: non_neg_integer()
}).

-endif.
