/*
Adapted from: https://github.com/succinctlabs/telepathy-circuits
*/

pragma circom 2.0.5;

include "../../ts/node_modules/circomlib/circuits/bitify.circom";
include "../../ts/node_modules/circomlib/circuits/binsum.circom";
include "./utils/constants.circom";
include "./utils/poseidon.circom";
include "./ssz.circom";

/*
 * Computes the Poseidon root of the sync committee.
 *
 * @input  pubkeysBytes             The sync committee pubkeys in bytes
 * @input  pubkeysBigIntX           The sync committee pubkeys in bigint form, X coordinate.
 * @input  pubkeysBigIntY           The sync committee pubkeys in bigint form, Y coordinate.
 * @input  syncCommitteeSSZ         A SSZ commitment to the sync committee
 */
template SyncCommitteePoseidon() {
    var N = getNumBitsPerRegister();
    var K = getNumRegisters();
    var SYNC_COMMITTEE_SIZE = getSyncCommitteeSize();
    var LOG_2_SYNC_COMMITTEE_SIZE = getLog2SyncCommitteeSize();
    var G1_POINT_SIZE = getG1PointSize();


    /* Sync Commmittee */
    signal input pubkeysBytes[SYNC_COMMITTEE_SIZE][G1_POINT_SIZE];
    signal input pubkeysBigIntX[SYNC_COMMITTEE_SIZE][K];
    signal input pubkeysBigIntY[SYNC_COMMITTEE_SIZE][K];
    signal input syncCommitteeSSZ[32];

    signal output syncCommitteePoseidon;

    /* VERIFY BYTE AND BIG INT REPRESENTATION OF G1 POINTS MATCH */
    component g1BytesToBigInt[SYNC_COMMITTEE_SIZE];
    for (var i = 0; i < SYNC_COMMITTEE_SIZE; i++) {
        g1BytesToBigInt[i] = G1BytesToBigInt(N, K, G1_POINT_SIZE);
        for (var j = 0; j < 48; j++) {
            g1BytesToBigInt[i].in[j] <== pubkeysBytes[i][j];
        }
        for (var j = 0; j < K; j++) {
            g1BytesToBigInt[i].out[j] === pubkeysBigIntX[i][j];
        }
    }

    /* VERIFY THE SSZ ROOT OF THE SYNC COMMITTEE */
    component sszSyncCommittee = SSZPhase0SyncCommittee(
        SYNC_COMMITTEE_SIZE,
        LOG_2_SYNC_COMMITTEE_SIZE,
        G1_POINT_SIZE
    );
    for (var i = 0; i < SYNC_COMMITTEE_SIZE; i++) {
        for (var j = 0; j < 48; j++) {
            sszSyncCommittee.pubkeys[i][j] <== pubkeysBytes[i][j];
        }
    }
    for (var i = 0; i < 48; i++) {
        sszSyncCommittee.aggregatePubkey[i] <== aggregatePubkeyBytes[i];
    }
    for (var i = 0; i < 32; i++) {
        syncCommitteeSSZ[i] === sszSyncCommittee.out[i];
    }

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

component main {public [syncCommitteeSSZ]} = SyncCommitteePoseidon();