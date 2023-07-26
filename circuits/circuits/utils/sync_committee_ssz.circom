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

include "../../../ts/node_modules/circomlib/circuits/bitify.circom";
include "../../../ts/node_modules/circomlib/circuits/binsum.circom";
include "./constants.circom";
include "./ssz.circom";

/*
 * Maps the SSZ commitment of the sync committee's pubkeys to a SNARK friendly
 * one using the Poseidon hash function. This is done once every sync committee
 * period to reduce the number of constraints (~70M) in the Step circuit. Called by rotate()
 * in the light client.
 *
 * @input  pubkeysBytes             The sync committee pubkeys in bytes
 * @input  aggregatePubkeyBytes     The aggregate sync committee pubkey in bytes
 * @input  syncCommitteeSSZ         A SSZ commitment to the sync committee
 */
template Rotate() {
    var SYNC_COMMITTEE_SIZE = getSyncCommitteeSize();
    var LOG_2_SYNC_COMMITTEE_SIZE = getLog2SyncCommitteeSize();
    var G1_POINT_SIZE = getG1PointSize();

    /* Sync Commmittee */
    signal input pubkeysBytes[SYNC_COMMITTEE_SIZE][G1_POINT_SIZE];
    signal input aggregatePubkeyBytes[G1_POINT_SIZE];
    signal input syncCommitteeSSZ[32];
    signal output syncCommitteeRoot[32];

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
}

component main { public [syncCommitteeSSZ] } = Rotate();