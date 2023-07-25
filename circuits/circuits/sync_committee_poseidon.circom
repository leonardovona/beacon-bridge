pragma circom 2.0.5;

include "./utils/constants.circom";
include "./utils/poseidon.circom";

/*
 * Computes the Poseidon root of the sync committee.
 *
 * @input  pubkeysBigIntX           The sync committee pubkeys in bigint form, X coordinate.
 * @input  pubkeysBigIntY           The sync committee pubkeys in bigint form, Y coordinate.
 */
template SyncCommitteePoseidon() {
    var N = getNumBitsPerRegister();
    var K = getNumRegisters();
    var SYNC_COMMITTEE_SIZE = getSyncCommitteeSize();

    /* Sync Commmittee */
    signal input pubkeysBigIntX[SYNC_COMMITTEE_SIZE][K];
    signal input pubkeysBigIntY[SYNC_COMMITTEE_SIZE][K];

    signal output syncCommitteePoseidon;


/* VERIFY THE POSEIDON ROOT OF THE SYNC COMMITTEE */
    component computePoseidonRoot = PoseidonG1Array(
        SYNC_COMMITTEE_SIZE,
        N,
        K
    );
    for (var i = 0; i < SYNC_COMMITTEE_SIZE; i++) {
        for (var j = 0; j < K; j++) {
            computePoseidonRoot.pubkeys[i][0][j] <== pubkeysBigIntX[i][j];
            computePoseidonRoot.pubkeys[i][1][j] <== pubkeysBigIntY[i][j];
        }
    }
    syncCommitteePoseidon <== computePoseidonRoot.out;
}

component main {public []} = SyncCommitteePoseidon();