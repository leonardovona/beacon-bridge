pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

//import "hardhat/console.sol";
import "./constants.sol";
import "./structs.sol";
import "./utils.sol";
import "./merkleize.sol";

contract LightClient {
    // Attributes
    Structs.LightClientStore store;
    Merkleize merkleize;

    event BootstrapComplete(uint64 slot);

    event UpdateProcessed(uint64 slot);

    constructor() { merkleize = new Merkleize(); }

    // This can avoided using constants
    function getSubtreeIndex(uint256 generalizedIndex) private pure returns (uint256) {
        return (generalizedIndex % (2**(Utils.log2({x: generalizedIndex, ceil: false}))));
    }

    function isValidMerkleBranch(
        bytes32 leaf,
        bytes32[] calldata branch,
        uint64 depth,
        uint256 index,
        bytes32 root
    ) private pure returns (bool) {
        // Check if ``leaf`` at ``index`` verifies against the Merkle ``root`` and ``branch``.
        bytes32 value = leaf;
        for (uint64 i; i < depth; ++i) {
            if (((index / (2**i)) % 2) != 0) {
                value = sha256(abi.encodePacked(branch[i], value));
            } else {
                value = sha256(abi.encodePacked(value, branch[i]));
            }
        }

        return value == root;
    }

    function isValidLightClientHeader(Structs.LightClientHeader calldata header) private view returns (bool) {
        return
            isValidMerkleBranch(
                merkleize.hashTreeRoot(header.execution),
                header.executionBranch,
                EXECUTION_PAYLOAD_INDEX_LOG_2,
                getSubtreeIndex(EXECUTION_PAYLOAD_INDEX),
                header.beacon.bodyRoot
            );
    }

    function initializeLightClientStore(Structs.LightClientBootstrap calldata bootstrap, bytes32 trustedBlockRoot) external {
        // Validate bootstrap
        require(isValidLightClientHeader(bootstrap.header));

        require(merkleize.hashTreeRoot(bootstrap.header.beacon) == trustedBlockRoot);

        bytes32 currentSyncCommitteeRoot = merkleize.hashTreeRoot(bootstrap.currentSyncCommittee);

        require(
            isValidMerkleBranch(
                currentSyncCommitteeRoot,
                bootstrap.currentSyncCommitteeBranch,
                CURRENT_SYNC_COMMITTEE_INDEX_LOG_2,
                getSubtreeIndex(CURRENT_SYNC_COMMITTEE_INDEX),
                bootstrap.header.beacon.stateRoot
            )
        );

        // Initialize store
        store.beaconSlot = bootstrap.header.beacon.slot;
        store.currentSyncCommitteeRoot = currentSyncCommitteeRoot;

        emit BootstrapComplete(bootstrap.header.beacon.slot);
    }

    // Not sure if this check is correct. There is for sure a better way to do this
    function isNextSyncCommitteeKnown() private view returns (bool) {
        return store.nextSyncCommitteeRoot != bytes32(0);
    }

    // Not sure if it is correct
    function isSyncCommitteeUpdate(Structs.LightClientUpdate calldata update) private pure returns (bool) {
        for (uint256 i; i < NEXT_SYNC_COMMITTEE_INDEX_LOG_2; ++i) {
            if (update.nextSyncCommitteeBranch[i] != bytes32(0)) { return true; }
        }
        return false;
    }

    function isFinalityUpdate(Structs.LightClientUpdate calldata update) private pure returns (bool) {
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

    function computeDomain(bytes4 forkVersion, bytes32 genesisValidatorsRoot) private view returns (bytes32) {
        //not sure
        bytes32[] memory chunks = new bytes32[](2);
        chunks[0] = bytes32(abi.encodePacked(forkVersion, bytes28(0)));
        chunks[1] = genesisValidatorsRoot;
        bytes32 forkDataRoot = merkleize.merkleize_chunks(chunks, 2);

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
        chunks[0] = merkleize.hashTreeRoot(beacon);
        chunks[1] = domain;

        return merkleize.merkleize_chunks(chunks, 2);
    }

    function validateLightClientUpdate(
        Structs.LightClientUpdate calldata update, 
        uint64 currentSlot, 
        bytes32 genesisValidatorsRoot, 
        Structs.SyncCommittee calldata syncCommittee
    ) private view {
        uint256 syncCommitteeParticipants;
        for (uint256 i; i < update.syncAggregate.syncCommitteeBits.length; ++i) {
            if (update.syncAggregate.syncCommitteeBits[i]) { ++syncCommitteeParticipants; }
        }
        require(syncCommitteeParticipants >= MIN_SYNC_COMMITTEE_PARTICIPANTS, "Not enough sync committee participants");

        require(isValidLightClientHeader(update.attestedHeader), "Invalid attested header");

        require(currentSlot >= update.signatureSlot, "Invalid signature slot");
        require(update.signatureSlot > update.attestedHeader.beacon.slot, "Invalid signature slot");
        require(update.attestedHeader.beacon.slot >= update.finalizedHeader.beacon.slot, "Invalid attested header slot");

        uint64 storePeriod = Utils.computeSyncCommitteePeriodAtSlot(store.beaconSlot);
        uint64 updateSignaturePeriod = Utils.computeSyncCommitteePeriodAtSlot(update.signatureSlot);

        if (isNextSyncCommitteeKnown()) {
            require((updateSignaturePeriod == storePeriod) || (updateSignaturePeriod == storePeriod + 1), "Invalid signature period");
        } else {
            require(updateSignaturePeriod == storePeriod, "Invalid signature period");
        }

        uint64 updateAttestedPeriod = Utils.computeSyncCommitteePeriodAtSlot(update.attestedHeader.beacon.slot);
        bool updateHasNextSyncCommittee = (!isNextSyncCommitteeKnown()) && (isSyncCommitteeUpdate(update) && (updateAttestedPeriod == storePeriod));

        require((update.attestedHeader.beacon.slot > store.beaconSlot) || updateHasNextSyncCommittee, "Invalid attested header slot");

        if (!isFinalityUpdate(update)) {
            // The finalized header must be empty
            require(update.finalizedHeader.beacon.bodyRoot == bytes32(0), "Invalid finalized header");
        } else {
            bytes32 finalizedRoot;
            if (update.finalizedHeader.beacon.slot == GENESIS_SLOT) {
                require(update.finalizedHeader.beacon.bodyRoot == bytes32(0), "Invalid finalized header");
            } else {
                require(isValidLightClientHeader(update.finalizedHeader), "Invalid finalized header");
                finalizedRoot = merkleize.hashTreeRoot(update.finalizedHeader.beacon);
            }
            require(
                isValidMerkleBranch(
                    finalizedRoot,
                    update.finalityBranch,
                    FINALIZED_ROOT_INDEX_LOG_2,
                    getSubtreeIndex(FINALIZED_ROOT_INDEX),
                    update.attestedHeader.beacon.stateRoot
                ), "Invalid finality branch"
            );
        }

        if (!isSyncCommitteeUpdate(update)) {
            Structs.SyncCommittee memory emptySyncCommittee;
            // This can be improved
            require(keccak256(update.nextSyncCommittee.aggregatePubkey) != keccak256(emptySyncCommittee.aggregatePubkey), "Invalid sync committee update");
        } else {
            if (updateAttestedPeriod == storePeriod && isNextSyncCommitteeKnown()
            ) {
                // This can be improved
                require(merkleize.hashTreeRoot(update.nextSyncCommittee) == store.nextSyncCommitteeRoot, "Invalid sync committee");
            }
            require(
                isValidMerkleBranch(
                    merkleize.hashTreeRoot(update.nextSyncCommittee),
                    update.nextSyncCommitteeBranch,
                    NEXT_SYNC_COMMITTEE_INDEX_LOG_2,
                    getSubtreeIndex(NEXT_SYNC_COMMITTEE_INDEX),
                    update.attestedHeader.beacon.stateRoot
                ), "Invalid sync committee branch"
            );
        }

        // Structs.SyncCommittee memory syncCommittee;
        if (updateSignaturePeriod == storePeriod) {
            require(merkleize.hashTreeRoot(syncCommittee) == store.currentSyncCommitteeRoot, "Invalid sync committee");
        } else {
            require(merkleize.hashTreeRoot(syncCommittee) == store.nextSyncCommitteeRoot, "Invalid sync committee");
        }

        bytes[] memory participantPubkeys = new bytes[](syncCommitteeParticipants);
        uint256 j;
        for (uint256 i; i < SYNC_COMMITTEE_SIZE; ++i) {
            if (update.syncAggregate.syncCommitteeBits[i]) {
                participantPubkeys[j] = (syncCommittee.pubkeys[i]);
                ++j;
            }
        }

        uint64 forkVersionSlot = (update.signatureSlot > 1 ? update.signatureSlot : 1) - 1;
        bytes4 forkVersion = computeForkVersion(Utils.computeEpochAtSlot(forkVersionSlot));
        bytes32 domain = computeDomain(forkVersion, genesisValidatorsRoot);

        bytes32 signingRoot = computeSigningRoot(update.attestedHeader.beacon, domain);

        // !! BLS signature verification, to implement
        //require(bls.fastAggregateVerify(participantPubkeys, signingRoot, update.syncAggregate.syncCommitteeSignature));
    }

    function applyLightClientUpdate( Structs.LightClientUpdate calldata update) private {
        uint64 storePeriod = Utils.computeSyncCommitteePeriodAtSlot(store.beaconSlot);
        uint64 updateFinalizedPeriod = Utils.computeSyncCommitteePeriodAtSlot(update.finalizedHeader.beacon.slot);

        if(!isNextSyncCommitteeKnown()){
            require(updateFinalizedPeriod == storePeriod, "Invalid finalized period");
            store.nextSyncCommitteeRoot = merkleize.hashTreeRoot(update.nextSyncCommittee);
        } else if(updateFinalizedPeriod == storePeriod + 1) {
            store.currentSyncCommitteeRoot = store.nextSyncCommitteeRoot;
            store.nextSyncCommitteeRoot = merkleize.hashTreeRoot(update.nextSyncCommittee);
            store.previousMaxActiveParticipants = store.currentMaxActiveParticipants;
            store.currentMaxActiveParticipants = 0;
        }
        if(update.finalizedHeader.beacon.slot > store.beaconSlot) {
            store.beaconSlot = update.finalizedHeader.beacon.slot;
        }
    }

    function processLightClientUpdate(
        Structs.LightClientUpdate calldata update,
        uint64 currentSlot,
        bytes32 genesisValidatorsRoot,
        Structs.SyncCommittee calldata syncCommittee
    ) external {
        validateLightClientUpdate(update, currentSlot, genesisValidatorsRoot, syncCommittee);
        bool[SYNC_COMMITTEE_SIZE] memory syncCommitteeBits = update.syncAggregate.syncCommitteeBits;

        uint64 currentParticipants;
        for (uint256 i; i < SYNC_COMMITTEE_SIZE; ++i) {
            if (syncCommitteeBits[i]) {++currentParticipants; }
        }

        bool updateHasFinalizedNextSyncCommittee = (
            !isNextSyncCommitteeKnown() &&
            isSyncCommitteeUpdate(update) &&
            isFinalityUpdate(update) &&
            (Utils.computeSyncCommitteePeriodAtSlot(update.finalizedHeader.beacon.slot) == Utils.computeSyncCommitteePeriodAtSlot(update.attestedHeader.beacon.slot))
        );

        if (currentParticipants * 3 >= SYNC_COMMITTEE_SIZE * 2 && ( update.finalizedHeader.beacon.slot > store.beaconSlot || updateHasFinalizedNextSyncCommittee)) {
            applyLightClientUpdate(update);
        }

        emit UpdateProcessed(update.attestedHeader.beacon.slot);
    }
}