pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import "./Constants.sol";
import "./Structs.sol";
import "./Utils.sol";
import "./Validator.sol";

// Verifier for the zkSNARK ssz-poseidon commitment mapping proof.
import "./PoseidonCommitmentVerifier.sol";

/*
* @dev The light client is a contract that stores the state of the beacon chain and allows to validate updates.
*/
contract LightClient is PoseidonCommitmentVerifier {
    // Attributes
    // Stores information used for the verification of the light client updates.
    Structs.LightClientStore store;
    // Validator contract used to validate the light client updates.
    Validator validator;

    // Stores the poseidon root for a given sync committee. Used to verify the header validity.
    mapping(bytes32 => bytes32) public sszToPoseidon;

    constructor() {
        validator = new Validator();
    }

    // Events
    // Emitted when the light client is initialized.
    event BootstrapComplete(uint64 slot);
    // Emitted when a light client update is processed.
    event UpdateProcessed(uint64 slot);

    // External functions
    /*
    * @dev Initializes the light client store with the given bootstrap.
    * @param bootstrap The bootstrap used to initialize the light client store.
    * @param trustedBlockRoot The root of the block that is trusted by the light client.
    * @param syncCommitteePoseidon The poseidon root of the sync committee.
    * @param proof The proof for the sync committee committment mapping.
    */
    function initializeLightClientStore(
        Structs.LightClientBootstrap calldata bootstrap, 
        bytes32 trustedBlockRoot,
        bytes32 syncCommitteePoseidon,
        Structs.Groth16Proof calldata proof  
    ) external {
        // Validate bootstrap.
        require(validator.isValidLightClientHeader(bootstrap.header));
        // Validate trusted block root.
        require(validator.hashTreeRoot(bootstrap.header.beacon) == trustedBlockRoot);
        // Validate sync committee.
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
        // Verify the commitment mapping proof.
        zkMapSSZToPoseidon(currentSyncCommitteeRoot, syncCommitteePoseidon, proof);

        // Initialize store.
        store.beaconSlot = bootstrap.header.beacon.slot;
        store.currentSyncCommitteeRoot = currentSyncCommitteeRoot;
        sszToPoseidon[currentSyncCommitteeRoot] = syncCommitteePoseidon;

        emit BootstrapComplete(bootstrap.header.beacon.slot);
    }

    // Struct used to store variables for the processLightClientUpdate function, to avoid stack too deep errors.
    struct ProcessLightClientUpdateVars {
        uint64 currentParticipants; // Number of participants in the sync committee.
        bool updateHasFinalizedNextSyncCommittee; // True if the update has finalized the next sync committee.
        bool isNextSyncCommitteeKnown; // True if the next sync committee is known.
        bool isSyncCommitteeUpdate; // True if the update is a sync committee update.
        bool isFinalityUpdate; // True if the update is a finality update.
        uint64 finalizedHeaderSyncCommitteePeriod; // The sync committee period of the finalized header.
        uint64 attestedHeaderSyncCommitteePeriod; // The sync committee period of the attested header.
    }

    /*
    * @dev Processes a light client update without a sync committee update.
    * @param update The light client update to process.
    * @param currentSlot The current slot of the beacon chain.
    * @param genesisValidatorsRoot The genesis validators root of the beacon chain.
    * @param syncCommittee The sync committee that signed the update.
    * @param signatureProof The proof that the sync committee signed the update.
    */
    function processLightClientUpdate(
        Structs.LightClientUpdate calldata update,
        uint64 currentSlot,
        bytes32 genesisValidatorsRoot,
        Structs.SyncCommittee calldata syncCommittee,
        Structs.Groth16Proof calldata signatureProof
    ) external { 
        // Validate update.
        bytes32 syncCommitteeRoot = validator.hashTreeRoot(syncCommittee);
        validator.validateLightClientUpdate(
            store, 
            update, 
            currentSlot, 
            genesisValidatorsRoot, 
            syncCommittee, 
            syncCommitteeRoot,
            sszToPoseidon[syncCommitteeRoot],
            signatureProof);

        ProcessLightClientUpdateVars memory vars;

        // Count the number of participants in the sync committee.
        for (uint256 i; i < SYNC_COMMITTEE_SIZE; ++i) {
            if (update.syncAggregate.syncCommitteeBits[i]) {++vars.currentParticipants; }
        }

        // Check if 2/3 of the sync committee signed the update and if the update is more recent than the current known value.
        if (vars.currentParticipants * 3 >= SYNC_COMMITTEE_SIZE * 2 && update.finalizedHeader.beacon.slot > store.beaconSlot) {
            store.beaconSlot = update.finalizedHeader.beacon.slot;
        }

        emit UpdateProcessed(update.finalizedHeader.beacon.slot);
    }

    /*
    * @dev Processes a light client update with a sync committee update.
    * @param update The light client update to process.
    * @param currentSlot The current slot of the beacon chain.
    * @param genesisValidatorsRoot The genesis validators root of the beacon chain.
    * @param syncCommittee The sync committee that signed the update.
    * @param nextSyncCommitteePoseidon The poseidon root of the next sync committee.
    * @param commitmentMappingProof The proof for the sync committee committment mapping.
    * @param signatureProof The proof that the sync committee signed the update.
    */
    function processLightClientUpdate(
        Structs.LightClientUpdate calldata update,
        uint64 currentSlot,
        bytes32 genesisValidatorsRoot,
        Structs.SyncCommittee calldata syncCommittee,
        bytes32 nextSyncCommitteePoseidon, 
        Structs.Groth16Proof memory commitmentMappingProof,
        Structs.Groth16Proof calldata signatureProof
    ) external {
        // Validate update.
        bytes32 syncCommitteeRoot = validator.hashTreeRoot(syncCommittee);
        validator.validateLightClientUpdate(
            store, 
            update, 
            currentSlot, 
            genesisValidatorsRoot, 
            syncCommittee, 
            syncCommitteeRoot,
            sszToPoseidon[syncCommitteeRoot],
            signatureProof);
        
        ProcessLightClientUpdateVars memory vars;

        // Count the number of participants in the sync committee.
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

        // Check if 2/3 of the sync committee signed the update and if either the update is more recent than the current known value or there is a sync committee update.
        if (vars.currentParticipants * 3 >= SYNC_COMMITTEE_SIZE * 2 && ( update.finalizedHeader.beacon.slot > store.beaconSlot || vars.updateHasFinalizedNextSyncCommittee)) {
            // Apply the update.
            applyLightClientUpdate(update, nextSyncCommitteePoseidon, commitmentMappingProof);
        }

        emit UpdateProcessed(update.finalizedHeader.beacon.slot);
    }

    /*
    * @dev Applies a light client update.
    * @param update The light client update to apply.
    * @param nextSyncCommitteePoseidon The poseidon root of the next sync committee.
    * @param commitmentMappingProof The proof for the sync committee committment mapping.
    */
    function applyLightClientUpdate(
        Structs.LightClientUpdate calldata update,
        bytes32 nextSyncCommitteePoseidon, 
        Structs.Groth16Proof memory commitmentMappingProof
    ) private {
        uint64 storePeriod = Utils.computeSyncCommitteePeriodAtSlot(store.beaconSlot);
        uint64 updateFinalizedPeriod = Utils.computeSyncCommitteePeriodAtSlot(update.finalizedHeader.beacon.slot);

        // Verify the proof for the sync committee committment mapping.
        bytes32 nextSyncCommitteeRoot = validator.hashTreeRoot(update.nextSyncCommittee);
        zkMapSSZToPoseidon(nextSyncCommitteeRoot, nextSyncCommitteePoseidon, commitmentMappingProof);

        
        if(!validator.isNextSyncCommitteeKnown(store.nextSyncCommitteeRoot)){ // if the next sync committee is not known
            require(updateFinalizedPeriod == storePeriod, "Invalid finalized period");
            store.nextSyncCommitteeRoot = validator.hashTreeRoot(update.nextSyncCommittee);
        } else if(updateFinalizedPeriod == storePeriod + 1) { // if the next sync committee is known and the update is for the next period
            store.currentSyncCommitteeRoot = store.nextSyncCommitteeRoot;
            store.nextSyncCommitteeRoot = validator.hashTreeRoot(update.nextSyncCommittee);
            store.previousMaxActiveParticipants = store.currentMaxActiveParticipants;
            store.currentMaxActiveParticipants = 0;
        }
        // Update the store slot if the update is more recent than the current known value.
        if(update.finalizedHeader.beacon.slot > store.beaconSlot) {
            store.beaconSlot = update.finalizedHeader.beacon.slot;
        }
    }

    /*
    * @author https://github.com/succinctlabs/eth-proof-of-consensus
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