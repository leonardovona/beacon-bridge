/*
 _____         _                       _     _           
|_   _|  ___  | |  ___   _ __   __ _  | |_  | |_    _  _ 
  | |   / -_) | | / -_) | '_ \ / _` | |  _| | ' \  | || |
  |_|   \___| |_| \___| | .__/ \__,_|  \__| |_||_|  \_, |
                        |_|                         |__/ 

Created on March 6th 2023 by Succinct Labs
Code: https://github.com/succinctlabs/telepathy-circuits
License: GPL-3
*/

pragma circom 2.0.5;

include "./utils/inputs.circom";
include "./utils/bls.circom";
include "./utils/constants.circom";
include "./utils/poseidon.circom";
include "./utils/ssz.circom";
include "./utils/sync_committee.circom";

/*
 * Maps the SSZ commitment of the sync committee's pubkeys to a SNARK friendly
 * one using the Poseidon hash function. This is done once every sync committee
 * period to reduce the number of constraints (~70M) in the Step circuit. Called by rotate()
 * in the light client.
 *
 * @input  pubkeysBigIntX           The sync committee pubkeys in bigint form, X coordinate.
 * @input  pubkeysBigIntY           The sync committee pubkeys in bigint form, Y coordinate.
 * @input  syncCommitteeSSZ         A SSZ commitment to the sync committee
 * @input  syncCommitteeBranch      A Merkle proof for the sync committee against finalizedHeader
 * @input  syncCommitteePoseidon    A Poseidon commitment ot the sync committee
 * @input  finalized{HeaderRoot,Slot,ProposerIndex,ParentRoot,StateRoot,BodyRoot}
                                    The finalized header and all associated fields.
 */
template Rotate() {
    var N = getNumBitsPerRegister();
    var K = getNumRegisters();
    var SYNC_COMMITTEE_SIZE = getSyncCommitteeSize();
    var SYNC_COMMITTEE_DEPTH = getSyncCommitteeDepth();
    var SYNC_COMMITTEE_INDEX = getSyncCommitteeIndex();
    var G1_POINT_SIZE = getG1PointSize();

    /* Sync Commmittee */
    signal input pubkeysBigIntX[SYNC_COMMITTEE_SIZE][K];
    signal input pubkeysBigIntY[SYNC_COMMITTEE_SIZE][K];
    signal input syncCommitteeSSZ[32];
    signal input syncCommitteeBranch[SYNC_COMMITTEE_DEPTH][32];
    signal input syncCommitteePoseidon;

    /* Finalized Header */
    signal input finalizedHeaderRoot[32];
    signal input finalizedSlot[32];
    signal input finalizedProposerIndex[32];
    signal input finalizedParentRoot[32];
    signal input finalizedStateRoot[32];
    signal input finalizedBodyRoot[32];

    /* VALIDATE FINALIZED HEADER AGAINST FINALIZED HEADER ROOT */
    component sszFinalizedHeader = SSZPhase0BeaconBlockHeader();
    for (var i = 0; i < 32; i++) {
        sszFinalizedHeader.slot[i] <== finalizedSlot[i];
        sszFinalizedHeader.proposerIndex[i] <== finalizedProposerIndex[i];
        sszFinalizedHeader.parentRoot[i] <== finalizedParentRoot[i];
        sszFinalizedHeader.stateRoot[i] <== finalizedStateRoot[i];
        sszFinalizedHeader.bodyRoot[i] <== finalizedBodyRoot[i];
    }
    for (var i = 0; i < 32; i++) {
        sszFinalizedHeader.out[i] === finalizedHeaderRoot[i];
    }

    /* CHECK SYNC COMMITTEE SSZ PROOF */
    component verifySyncCommittee = SSZRestoreMerkleRoot(
        SYNC_COMMITTEE_DEPTH,
        SYNC_COMMITTEE_INDEX
    );
    for (var i = 0; i < 32; i++) {
        verifySyncCommittee.leaf[i] <== syncCommitteeSSZ[i];
        for (var j = 0; j < SYNC_COMMITTEE_DEPTH; j++) {
            verifySyncCommittee.branch[j][i] <== syncCommitteeBranch[j][i];
        }
    }
    for (var i = 0; i < 32; i++) {
        verifySyncCommittee.out[i] === finalizedStateRoot[i];
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
    syncCommitteePoseidon === computePoseidonRoot.out;
}

component main {public [syncCommitteeSSZ, syncCommitteePoseidon, finalizedHeaderRoot]} = Rotate();