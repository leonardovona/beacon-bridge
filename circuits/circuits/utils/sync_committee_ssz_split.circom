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
    var SYNC_COMMITTEE_SIZE = 256;
    var LOG_2_SYNC_COMMITTEE_SIZE = 8;
    var G1_POINT_SIZE = getG1PointSize();

    /* Sync Commmittee */
    signal input pubkeysBytes[SYNC_COMMITTEE_SIZE][G1_POINT_SIZE];
    signal output pubkeysSSZ[32];

    /* VERIFY THE SSZ ROOT OF THE SYNC COMMITTEE */
    component sszPubkeys = SSZArray(
        SYNC_COMMITTEE_SIZE * 64,
        LOG_2_SYNC_COMMITTEE_SIZE + 1
    );
    for (var i = 0; i < SYNC_COMMITTEE_SIZE; i++) {
        for (var j = 0; j < 64; j++) {
            if (j < G1_POINT_SIZE) {
                sszPubkeys.in[i * 64 + j] <== pubkeysBytes[i][j];
            } else {
                sszPubkeys.in[i * 64 + j] <== 0;
            }
        }
    }

    for (var i = 0; i < 32; i++) {
        pubkeysSSZ[i] <== sszPubkeys.out[i];
    }
}

component main = Rotate();