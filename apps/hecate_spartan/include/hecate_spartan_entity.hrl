-ifndef(HECATE_SPARTAN_ENTITY_HRL).
-define(HECATE_SPARTAN_ENTITY_HRL, true).

%% Entity aggregate status — bit flags (powers of 2), manipulated via
%% evoq_bit_flags. Status is an integer, never an atom.
-define(ENTITY_REGISTERED, 1).   %% 2^0
-define(ENTITY_SUSPENDED,  2).   %% 2^1

-record(entity_state, {
    did           :: binary() | undefined,
    entity_name   :: binary() | undefined,
    pubkey        :: binary() | undefined,
    status = 0    :: non_neg_integer(),
    registered_at :: integer() | undefined
}).

-endif.
