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

include "./utils/bls.circom";
include "./utils/constants.circom";
include "./utils/poseidon.circom";
include "./utils/sync_committee.circom";

/*
 * Reduces the gas cost of processing a light client update by offloading the 
 * verification of the aggregated BLS signature by the sync committee and 
 * various merkle proofs (e.g., finality) into a zkSNARK which can be verified
 * on-chain for ~200K gas. 
 *
 * @input  pubkeysX               X-coordinate of the public keys of the sync committee in bigint form.
 * @input  pubkeysY               Y-coordinate of the public keys of the sync committee in bigint form.
 * @input  aggregationBits        Bitmap indicating which validators have signed
 * @input  signature              An aggregated signature over signingRoot
 * @input  signingRoot            sha256(attestedHeaderRoot, domain)
 * @input  participation          sum(aggregationBits)
 * @input  syncCommitteePoseidon  A commitment to the sync committee pubkeys from rotate.circom.
 */
template Step() {
    var N = getNumBitsPerRegister();
    var K = getNumRegisters();
    var SYNC_COMMITTEE_SIZE = getSyncCommitteeSize();
    var LOG_2_SYNC_COMMITTEE_SIZE = getLog2SyncCommitteeSize();

    // /* Sync Committee Protocol */
    signal input pubkeysX[SYNC_COMMITTEE_SIZE][K];
    signal input pubkeysY[SYNC_COMMITTEE_SIZE][K];
    signal input aggregationBits[SYNC_COMMITTEE_SIZE];
    signal input signature[2][2][K];
    signal input signingRoot[32];
    signal input participation;
    signal input syncCommitteePoseidon;

    /* VERIFY SYNC COMMITTEE SIGNATURE AND COMPUTE PARTICIPATION */
    component verifySignature = VerifySyncCommitteeSignature(
        SYNC_COMMITTEE_SIZE,
        LOG_2_SYNC_COMMITTEE_SIZE,
        N,
        K
    );
    for (var i = 0; i < SYNC_COMMITTEE_SIZE; i++) {
        verifySignature.aggregationBits[i] <== aggregationBits[i];
        for (var j = 0; j < K; j++) {
            verifySignature.pubkeys[i][0][j] <== pubkeysX[i][j];
            verifySignature.pubkeys[i][1][j] <== pubkeysY[i][j];
        }
    }
    for (var i = 0; i < 2; i++) {
        for (var j = 0; j < 2; j++) {
            for (var l = 0; l < K; l++) {
                verifySignature.signature[i][j][l] <== signature[i][j][l];
            }
        }
    }
    for (var i = 0; i < 32; i++) {
        verifySignature.signingRoot[i] <== signingRoot[i];
    }
    verifySignature.syncCommitteeRoot <== syncCommitteePoseidon;
    verifySignature.participation === participation;  
}

component main {public [syncCommitteePoseidon, signingRoot]} = Step();
