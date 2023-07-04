pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

//import "hardhat/console.sol";
import "./Constants.sol";
import "./Structs.sol";
import "./Utils.sol";
import "./Merkleize.sol";

import "./BLSAggregatedSignatureVerifier.sol";

contract Validator is BLSAggregatedSignatureVerifier, Merkleize {
    // Attributes
    mapping(bytes32 => bytes32) public sszToPoseidon;

    // Events
    event BootstrapComplete(uint64 slot);

    event UpdateProcessed(uint64 slot);

    // This is to avoid stack too deep
    struct LightClientUpdateVars {
        uint64 syncCommitteeParticipants;
        uint64 storePeriod;
        uint64 updateSignaturePeriod;
        uint64 updateAttestedPeriod;
        bool updateHasNextSyncCommittee;
        Structs.SyncCommittee emptySyncCommittee;
        bytes32 finalizedRoot;
        bytes32 syncCommitteeRoot;
        bytes[] participantPubkeys;
        bytes32 signingRoot;
    }

    function validateLightClientUpdate(
        Structs.LightClientStore memory store,
        Structs.LightClientUpdate calldata update, 
        uint64 currentSlot, 
        bytes32 genesisValidatorsRoot, 
        Structs.SyncCommittee calldata syncCommittee,
        Structs.Groth16Proof calldata proof
    ) public view{
        LightClientUpdateVars memory vars;
        for (uint256 i; i < update.syncAggregate.syncCommitteeBits.length; ++i) {
            if (update.syncAggregate.syncCommitteeBits[i]) { ++vars.syncCommitteeParticipants; }
        }
        require(vars.syncCommitteeParticipants >= MIN_SYNC_COMMITTEE_PARTICIPANTS, "Not enough sync committee participants");

        require(isValidLightClientHeader(update.attestedHeader), "Invalid attested header");

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

        if (!isSyncCommitteeUpdate(update)) {
            // This can be improved
            require(keccak256(update.nextSyncCommittee.aggregatePubkey) != keccak256(vars.emptySyncCommittee.aggregatePubkey), "Invalid sync committee update");
        } else {
            if (vars.updateAttestedPeriod == vars.storePeriod && isNextSyncCommitteeKnown(store.nextSyncCommitteeRoot)
            ) {
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

        // Structs.SyncCommittee memory syncCommittee;
        vars.syncCommitteeRoot = hashTreeRoot(syncCommittee);
        if (vars.updateSignaturePeriod == vars.storePeriod) {
            require(vars.syncCommitteeRoot == store.currentSyncCommitteeRoot, "Invalid sync committee");
        } else {
            require(vars.syncCommitteeRoot == store.nextSyncCommitteeRoot, "Invalid sync committee");
        }

        vars.participantPubkeys = new bytes[](vars.syncCommitteeParticipants);
        uint256 j;
        for (uint256 i; i < SYNC_COMMITTEE_SIZE; ++i) {
            if (update.syncAggregate.syncCommitteeBits[i]) {
                vars.participantPubkeys[j] = (syncCommittee.pubkeys[i]);
                ++j;
            }
        }

        vars.signingRoot = computeSigningRoot(
            update.attestedHeader.beacon, 
            computeDomain(
                computeForkVersion(Utils.computeEpochAtSlot((update.signatureSlot > 1 ? update.signatureSlot : 1) - 1)),
                genesisValidatorsRoot
            )
        );

        // !! BLS signature verification
        require(zkBLSVerify(vars.signingRoot, vars.syncCommitteeRoot, vars.syncCommitteeParticipants, proof), "Signature is invalid");
    }

    /*
    * @dev Does an aggregated BLS signature verification with a zkSNARK. The proof asserts that:
    *   Poseidon(validatorPublicKeys) == sszToPoseidon[syncCommitteeRoot]
    *   aggregatedPublicKey = InnerProduct(validatorPublicKeys, bitmap)
    *   BLSVerify(aggregatedPublicKey, signature) == true
    */
    function zkBLSVerify(
        bytes32 signingRoot, 
        bytes32 syncCommitteeRoot, 
        uint256 claimedParticipation, 
        Structs.Groth16Proof memory proof
    ) internal view returns (bool) {
        require(sszToPoseidon[syncCommitteeRoot] != 0, "Must map SSZ commitment to Posedion commitment");
        uint256[34] memory inputs;
        inputs[0] = claimedParticipation;
        inputs[1] = uint256(sszToPoseidon[syncCommitteeRoot]);
        uint256 signingRootNumeric = uint256(signingRoot);
        for (uint256 i = 0; i < 32; i++) {
            inputs[(32 - 1 - i) + 2] = signingRootNumeric % 2 ** 8;
            signingRootNumeric = signingRootNumeric / 2**8;
        }
        return verifySignatureProof(proof.a, proof.b, proof.c, inputs);
    }

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

    // Not sure if this check is correct. There is for sure a better way to do this
    function isNextSyncCommitteeKnown(bytes32 nextSyncCommitteeRoot) public pure returns (bool) {
        return nextSyncCommitteeRoot != bytes32(0);
    }

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

    function computeSigningRoot(Structs.BeaconBlockHeader calldata beacon, bytes32 domain) private view returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](2);
        chunks[0] = hashTreeRoot(beacon);
        chunks[1] = domain;

        return merkleize_chunks(chunks, 2);
    }

    // Not sure if it is correct
    function isSyncCommitteeUpdate(Structs.LightClientUpdate calldata update) public pure returns (bool) {
        for (uint256 i; i < NEXT_SYNC_COMMITTEE_INDEX_LOG_2; ++i) {
            if (update.nextSyncCommitteeBranch[i] != bytes32(0)) { return true; }
        }
        return false;
    }

    function isFinalityUpdate(Structs.LightClientUpdate calldata update) public pure returns (bool) {
        for (uint256 i; i < FINALIZED_ROOT_INDEX_LOG_2; ++i) {
            if (update.finalityBranch[i] != bytes32(0)) { return true; }
        }
        return false;
    }

    function computeForkVersion(uint256 epoch) private pure returns (bytes4) {
        if (epoch >= CAPELLA_FORK_EPOCH) return CAPELLA_FORK_VERSION;
        if (epoch >= BELLATRIX_FORK_EPOCH) return BELLATRIX_FORK_VERSION;
        if (epoch >= ALTAIR_FORK_EPOCH) return ALTAIR_FORK_VERSION;
        return GENESIS_FORK_VERSION;
    }
}