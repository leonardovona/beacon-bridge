pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import "./Constants.sol";
import "./Structs.sol";
import "./Utils.sol";
import "./Validator.sol";

import "./PoseidonCommitmentVerifier.sol";

contract LightClient is PoseidonCommitmentVerifier {
    // Attributes
    Structs.LightClientStore store;
    Validator validator;

    mapping(bytes32 => bytes32) public sszToPoseidon;

    constructor() {
        validator = new Validator();
    }

    // Events
    event BootstrapComplete(uint64 slot);

    event UpdateProcessed(uint64 slot);

    // External functions
    function initializeLightClientStore(
        Structs.LightClientBootstrap calldata bootstrap, 
        bytes32 trustedBlockRoot,
        bytes32 syncCommitteePoseidon,
        Structs.Groth16Proof calldata proof  
    ) external {
        // Validate bootstrap
        require(validator.isValidLightClientHeader(bootstrap.header));

        require(validator.hashTreeRoot(bootstrap.header.beacon) == trustedBlockRoot);

        bytes32 currentSyncCommitteeRoot = validator.hashTreeRoot(bootstrap.currentSyncCommittee);

        require(
            validator.isValidMerkleBranch(
                currentSyncCommitteeRoot,
                bootstrap.currentSyncCommitteeBranch,
                CURRENT_SYNC_COMMITTEE_INDEX_LOG_2,
                Utils.getSubtreeIndex(CURRENT_SYNC_COMMITTEE_INDEX),
                bootstrap.header.beacon.stateRoot
            )
        );

        zkMapSSZToPoseidon(currentSyncCommitteeRoot, syncCommitteePoseidon, proof);

        // Initialize store
        store.beaconSlot = bootstrap.header.beacon.slot;
        store.currentSyncCommitteeRoot = currentSyncCommitteeRoot;
        sszToPoseidon[currentSyncCommitteeRoot] = syncCommitteePoseidon; // we should verify that the poseidon corresponds to the root, using zk proof (like in processLightClientUpdate)

        emit BootstrapComplete(bootstrap.header.beacon.slot);
    }

    struct ProcessLightClientUpdateVars {
        uint64 currentParticipants;
        bool updateHasFinalizedNextSyncCommittee;
        bool isNextSyncCommitteeKnown;
        bool isSyncCommitteeUpdate;
        bool isFinalityUpdate;
        uint64 finalizedHeaderSyncCommitteePeriod;
        uint64 attestedHeaderSyncCommitteePeriod;
    }

    function processLightClientUpdate(
        Structs.LightClientUpdate calldata update,
        uint64 currentSlot,
        bytes32 genesisValidatorsRoot,
        Structs.SyncCommittee calldata syncCommittee,
        Structs.Groth16Proof calldata signatureProof
    ) external { 
        validator.validateLightClientUpdate(store, update, currentSlot, genesisValidatorsRoot, syncCommittee, signatureProof);
        ProcessLightClientUpdateVars memory vars;

        for (uint256 i; i < SYNC_COMMITTEE_SIZE; ++i) {
            if (update.syncAggregate.syncCommitteeBits[i]) {++vars.currentParticipants; }
        }
       
        if (vars.currentParticipants * 3 >= SYNC_COMMITTEE_SIZE * 2 && update.finalizedHeader.beacon.slot > store.beaconSlot) {
            store.beaconSlot = update.finalizedHeader.beacon.slot;
        }

        emit UpdateProcessed(update.attestedHeader.beacon.slot);
    }

    function processLightClientUpdate(
        Structs.LightClientUpdate calldata update,
        uint64 currentSlot,
        bytes32 genesisValidatorsRoot,
        Structs.SyncCommittee calldata syncCommittee,
        bytes32 nextSyncCommitteePoseidon, 
        Structs.Groth16Proof memory commitmentMappingProof,
        Structs.Groth16Proof calldata signatureProof
    ) external {
        validator.validateLightClientUpdate(store, update, currentSlot, genesisValidatorsRoot, syncCommittee, signatureProof);
        ProcessLightClientUpdateVars memory vars;

        for (uint256 i; i < SYNC_COMMITTEE_SIZE; ++i) {
            if (update.syncAggregate.syncCommitteeBits[i]) {++vars.currentParticipants; }
        }

        vars.isNextSyncCommitteeKnown = validator.isNextSyncCommitteeKnown(store.nextSyncCommitteeRoot);
        vars.isSyncCommitteeUpdate = validator.isSyncCommitteeUpdate(update);
        vars.isFinalityUpdate = validator.isFinalityUpdate(update);
        vars.finalizedHeaderSyncCommitteePeriod = Utils.computeSyncCommitteePeriodAtSlot(update.finalizedHeader.beacon.slot);
        vars.attestedHeaderSyncCommitteePeriod = Utils.computeSyncCommitteePeriodAtSlot(update.attestedHeader.beacon.slot);
        
        vars.updateHasFinalizedNextSyncCommittee = (
            !vars.isNextSyncCommitteeKnown &&
            vars.isSyncCommitteeUpdate &&
            vars.isFinalityUpdate &&
            (vars.finalizedHeaderSyncCommitteePeriod == vars.attestedHeaderSyncCommitteePeriod)
        );

        if (vars.currentParticipants * 3 >= SYNC_COMMITTEE_SIZE * 2 && ( update.finalizedHeader.beacon.slot > store.beaconSlot || vars.updateHasFinalizedNextSyncCommittee)) {
            applyLightClientUpdate(update, nextSyncCommitteePoseidon, commitmentMappingProof);
        }

        emit UpdateProcessed(update.attestedHeader.beacon.slot);
    }

    function applyLightClientUpdate(
        Structs.LightClientUpdate calldata update,
        bytes32 nextSyncCommitteePoseidon, 
        Structs.Groth16Proof memory commitmentMappingProof
    ) private {
        uint64 storePeriod = Utils.computeSyncCommitteePeriodAtSlot(store.beaconSlot);
        uint64 updateFinalizedPeriod = Utils.computeSyncCommitteePeriodAtSlot(update.finalizedHeader.beacon.slot);

        bytes32 nextSyncCommitteeRoot = validator.hashTreeRoot(update.nextSyncCommittee);
        zkMapSSZToPoseidon(nextSyncCommitteeRoot, nextSyncCommitteePoseidon, commitmentMappingProof);

        if(!validator.isNextSyncCommitteeKnown(store.nextSyncCommitteeRoot)){
            require(updateFinalizedPeriod == storePeriod, "Invalid finalized period");
            store.nextSyncCommitteeRoot = validator.hashTreeRoot(update.nextSyncCommittee);
        } else if(updateFinalizedPeriod == storePeriod + 1) {
            store.currentSyncCommitteeRoot = store.nextSyncCommitteeRoot;
            store.nextSyncCommitteeRoot = validator.hashTreeRoot(update.nextSyncCommittee);
            store.previousMaxActiveParticipants = store.currentMaxActiveParticipants;
            store.currentMaxActiveParticipants = 0;
        }
        if(update.finalizedHeader.beacon.slot > store.beaconSlot) {
            store.beaconSlot = update.finalizedHeader.beacon.slot;
        }
    }

        /*
    * @dev Maps a simple serialize merkle root to a poseidon merkle root with a zkSNARK. The proof asserts that:
    *   SimpleSerialize(syncCommittee) == Poseidon(syncCommittee).
    */
    function zkMapSSZToPoseidon(bytes32 sszCommitment, bytes32 poseidonCommitment, Structs.Groth16Proof memory proof) private {
        uint256[33] memory inputs; // inputs is syncCommitteeSSZ[0..32] + [syncCommitteePoseidon]
        uint256 sszCommitmentNumeric = uint256(sszCommitment);
        for (uint256 i = 0; i < 32; i++) {
            inputs[32 - 1 - i] = sszCommitmentNumeric % 2**8;
            sszCommitmentNumeric = sszCommitmentNumeric / 2**8;
        }
        inputs[32] = uint256(poseidonCommitment);
        require(verifyCommitmentMappingProof(proof.a, proof.b, proof.c, inputs), "Proof is invalid");
        sszToPoseidon[sszCommitment] = poseidonCommitment;
    }
}