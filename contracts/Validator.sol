pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import "./Constants.sol";
import "./Structs.sol";
import "./Utils.sol";
import "./Merkleize.sol";

// Verifier for the BLS signature validity proof
import "./BLSAggregatedSignatureVerifier.sol";

/*
* @dev This contract implements the light client update validation logic.
*/
contract Validator is BLSAggregatedSignatureVerifier, Merkleize {

    // Struct to store variables for the validateLightClientUpdate function, to avoid stack too deep errors.
    struct LightClientUpdateVars {
        uint64 syncCommitteeParticipants;
        uint64 storePeriod;
        uint64 updateSignaturePeriod;
        uint64 updateAttestedPeriod;
        bool updateHasNextSyncCommittee;
        Structs.SyncCommittee emptySyncCommittee;
        bytes32 finalizedRoot;
        bytes[] participantPubkeys;
        bytes32 signingRoot;
    }

    /*
    * @dev Validates a light client update.
    * @param store The light client store.
    * @param update The light client update.
    * @param currentSlot The current slot.
    * @param syncCommitteePoseidonRoot The Poseidon hash of the sync committee.
    * @param proof The proof that syncCommittee has signed the update.
    */
    function validateLightClientUpdate(
        Structs.LightClientStore memory store,
        Structs.LightClientUpdate calldata update, 
        uint64 currentSlot,
        bytes32 syncCommitteePoseidonRoot,
        Structs.Groth16Proof calldata proof
    ) public view{
        LightClientUpdateVars memory vars;

        // Calculate the number of participants in the sync committee.
        for (uint256 i; i < update.syncAggregate.syncCommitteeBits.length; ++i) {
            if (update.syncAggregate.syncCommitteeBits[i]) { ++vars.syncCommitteeParticipants; }
        }
        require(vars.syncCommitteeParticipants >= MIN_SYNC_COMMITTEE_PARTICIPANTS, "Not enough sync committee participants");

        // Verifies that the attested header is valid.
        require(isValidLightClientHeader(update.attestedHeader), "Invalid attested header");

        // Verifies that the slots are valid.
        require(currentSlot >= update.signatureSlot, "Invalid signature slot");
        require(update.signatureSlot > update.attestedHeader.beacon.slot, "Invalid signature slot");
        require(update.attestedHeader.beacon.slot >= update.finalizedHeader.beacon.slot, "Invalid attested header slot");

        vars.storePeriod = Utils.computeSyncCommitteePeriodAtSlot(store.beaconSlot);
        vars.updateSignaturePeriod = Utils.computeSyncCommitteePeriodAtSlot(update.signatureSlot);

        if (isNextSyncCommitteeKnown(store.nextSyncCommitteeRoot)) {
            require((vars.updateSignaturePeriod == vars.storePeriod) || (vars.updateSignaturePeriod == vars.storePeriod + 1), "Invalid signature period");
        } else {
            require(vars.updateSignaturePeriod == vars.storePeriod, "Invalid signature period");
        }

        vars.updateAttestedPeriod = Utils.computeSyncCommitteePeriodAtSlot(update.attestedHeader.beacon.slot);
        vars.updateHasNextSyncCommittee = (!isNextSyncCommitteeKnown(store.nextSyncCommitteeRoot)) && (isSyncCommitteeUpdate(update) && (vars.updateAttestedPeriod == vars.storePeriod));

        require((update.attestedHeader.beacon.slot > store.beaconSlot) || vars.updateHasNextSyncCommittee, "Invalid attested header slot");

        // Finalized header verification
        if (!isFinalityUpdate(update)) {
            // The finalized header must be empty
            require(update.finalizedHeader.beacon.bodyRoot == bytes32(0), "Invalid finalized header");
        } else {
            if (update.finalizedHeader.beacon.slot == GENESIS_SLOT) {
                require(update.finalizedHeader.beacon.bodyRoot == bytes32(0), "Invalid finalized header");
            } else {
                require(isValidLightClientHeader(update.finalizedHeader), "Invalid finalized header");
                vars.finalizedRoot = hashTreeRoot(update.finalizedHeader.beacon);
            }
            require(
                isValidMerkleBranch(
                    vars.finalizedRoot,
                    update.finalityBranch,
                    FINALIZED_ROOT_INDEX_LOG_2,
                    Utils.getSubtreeIndex(FINALIZED_ROOT_INDEX),
                    update.attestedHeader.beacon.stateRoot
                ), "Invalid finality branch"
            );
        }

        // Sync committee verification
        if (!isSyncCommitteeUpdate(update)) {
            // This can be improved
            require(keccak256(update.nextSyncCommittee.aggregatePubkey) != keccak256(vars.emptySyncCommittee.aggregatePubkey), "Invalid sync committee update");
        } else {
            if (vars.updateAttestedPeriod == vars.storePeriod && isNextSyncCommitteeKnown(store.nextSyncCommitteeRoot)) {
                // This can be improved
                require(hashTreeRoot(update.nextSyncCommittee) == store.nextSyncCommitteeRoot, "Invalid sync committee");
            }
            require(
                isValidMerkleBranch(
                    hashTreeRoot(update.nextSyncCommittee),
                    update.nextSyncCommitteeBranch,
                    NEXT_SYNC_COMMITTEE_INDEX_LOG_2,
                    Utils.getSubtreeIndex(NEXT_SYNC_COMMITTEE_INDEX),
                    update.attestedHeader.beacon.stateRoot
                ), "Invalid sync committee branch"
            );
        }
      
        // Compute the signing root
        vars.signingRoot = computeSigningRoot(
            update.attestedHeader.beacon, 
            computeDomain(
                computeForkVersion(Utils.computeEpochAtSlot((update.signatureSlot > 1 ? update.signatureSlot : 1) - 1)),
                store.genesisValidatorsRoot
            )
        );

        // BLS signature proof verification
        require(zkBLSVerify(vars.signingRoot, syncCommitteePoseidonRoot, proof), "Signature is invalid");
    }

    /*
    * @author https://github.com/succinctlabs/eth-proof-of-consensus
    * @dev Does an aggregated BLS signature verification with a zkSNARK. The proof asserts that:
    *   Poseidon(validatorPublicKeys) == sszToPoseidon[syncCommitteeRoot]
    *   aggregatedPublicKey = InnerProduct(validatorPublicKeys, bitmap)
    *   BLSVerify(aggregatedPublicKey, signature) == true
    */
    function zkBLSVerify(
        bytes32 signingRoot, 
        bytes32 syncCommitteePoseidonRoot,
        Structs.Groth16Proof memory proof
    ) internal view returns (bool) {
        require(syncCommitteePoseidonRoot != 0, "Must map SSZ commitment to Poseidon commitment");
        uint256[33] memory inputs;
        inputs[0] = uint256(syncCommitteePoseidonRoot);
        uint256 signingRootNumeric = uint256(signingRoot);
        for (uint256 i = 0; i < 32; i++) {
            inputs[(32 - 1 - i) + 1] = signingRootNumeric % 2 ** 8;
            signingRootNumeric = signingRootNumeric / 2**8;
        }
        return verifySignatureProof(proof.a, proof.b, proof.c, inputs);
    }

    /*
    * @dev Verifies that a light client header is valid by verifying the Merkle proof.
    * @param header The light client header.
    * @return True if the header is valid, false otherwise.
    */
    function isValidLightClientHeader(Structs.LightClientHeader calldata header) public view returns (bool) {
        return
            isValidMerkleBranch(
                hashTreeRoot(header.execution),
                header.executionBranch,
                EXECUTION_PAYLOAD_INDEX_LOG_2,
                Utils.getSubtreeIndex(EXECUTION_PAYLOAD_INDEX),
                header.beacon.bodyRoot
            );
    }

    /*
    * @dev Checks if the next sync committee is known.
    * @param nextSyncCommitteeRoot The root of the next sync committee.
    * @return True if the next sync committee is known, false otherwise.
    */
    function isNextSyncCommitteeKnown(bytes32 nextSyncCommitteeRoot) public pure returns (bool) {
        return nextSyncCommitteeRoot != bytes32(0);
    }

    /*
    * @dev Computes the Ethereum beacon chain domain (see the specs for details).
    * @param forkVersion The fork version.
    * @param genesisValidatorsRoot The genesis validators root.
    * @return The domain.
    */
    function computeDomain(bytes4 forkVersion, bytes32 genesisValidatorsRoot) private view returns (bytes32) {
        //not sure
        bytes32[] memory chunks = new bytes32[](2);
        chunks[0] = bytes32(abi.encodePacked(forkVersion, bytes28(0)));
        chunks[1] = genesisValidatorsRoot;
        bytes32 forkDataRoot = merkleize_chunks(chunks, 2);

        // not sure
        bytes memory domain = new bytes(32);
        domain[0] = DOMAIN_SYNC_COMMITTEE[0];
        domain[1] = DOMAIN_SYNC_COMMITTEE[1];
        domain[2] = DOMAIN_SYNC_COMMITTEE[2];
        domain[3] = DOMAIN_SYNC_COMMITTEE[3];
        for (uint256 i = 4; i < 32; ++i) { domain[i] = forkDataRoot[i]; }
        return bytes32(domain);
    }

    /*
    * @dev Computes the signing root (see the specs for details).
    * @param beacon The beacon block header.
    * @param domain The domain.
    * @return The signing root.
    */
    function computeSigningRoot(Structs.BeaconBlockHeader calldata beacon, bytes32 domain) private view returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](2);
        chunks[0] = hashTreeRoot(beacon);
        chunks[1] = domain;

        return merkleize_chunks(chunks, 2);
    }

    /*
    * @dev Checks if the update is a sync committee update.
    * @param update The light client update.
    * @return True if the update is a sync committee update, false otherwise.
    */
    function isSyncCommitteeUpdate(Structs.LightClientUpdate calldata update) public pure returns (bool) {
        // Not sure if it is correct
        for (uint256 i; i < NEXT_SYNC_COMMITTEE_INDEX_LOG_2; ++i) {
            if (update.nextSyncCommitteeBranch[i] != bytes32(0)) { return true; }
        }
        return false;
    }

    /*
    * @dev Checks if the update is a finality update.
    * @param update The light client update.
    * @return True if the update is a finality update, false otherwise.
    */
    function isFinalityUpdate(Structs.LightClientUpdate calldata update) public pure returns (bool) {
        for (uint256 i; i < FINALIZED_ROOT_INDEX_LOG_2; ++i) {
            if (update.finalityBranch[i] != bytes32(0)) { return true; }
        }
        return false;
    }

    /*
    * @dev Computes the fork version for a given epoch.
    * @param epoch The epoch.
    * @return The fork version.
    */
    function computeForkVersion(uint256 epoch) private pure returns (bytes4) {
        if (epoch >= CAPELLA_FORK_EPOCH) return CAPELLA_FORK_VERSION;
        if (epoch >= BELLATRIX_FORK_EPOCH) return BELLATRIX_FORK_VERSION;
        if (epoch >= ALTAIR_FORK_EPOCH) return ALTAIR_FORK_VERSION;
        return GENESIS_FORK_VERSION;
    }
}