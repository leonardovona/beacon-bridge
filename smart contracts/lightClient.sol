pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";
import "./constants.sol";
import "./structs.sol";
import "./utils.sol";
import "./merkleize.sol";

contract LightClient {
    // Attributes
    Structs.LightClientStore store;
    Merkleize merkleize;

    constructor() {
        merkleize = new Merkleize();
    }

    function getSubtreeIndex(uint256 generalizedIndex)
        private
        pure
        returns (uint256)
    {
        return (generalizedIndex %
            (2**(Utils.log2({x: generalizedIndex, ceil: false}))));
    }

    function isEmptyExecutionPayloadHeader(
        Structs.ExecutionPayloadHeader memory header
    ) private pure returns (bool) {
        for (uint16 i = 0; i < BYTES_PER_LOGS_BLOOM; i++) {
            if (header.logsBloom[i] != "") return false;
        }

        for (uint256 i = 0; i < header.extraData.length; i++) {
            if (header.extraData[i] != "") return false;
        }

        return (header.parentHash == "" &&
            header.feeRecipient == "" &&
            header.stateRoot == "" &&
            header.receiptsRoot == "" &&
            header.prevRandao == "" &&
            header.blockNumber == 0 &&
            header.gasLimit == 0 &&
            header.gasUsed == 0 &&
            header.timestamp == 0 &&
            header.baseFeePerGas == 0 &&
            header.blockHash == "" &&
            header.transactionsRoot == "" &&
            header.withdrawalsRoot == "");
    }

    function isEmptyExecutionBranch(bytes32[] memory executionBranch)
        private
        pure
        returns (bool)
    {
        for (uint8 i = 0; i < EXECUTION_PAYLOAD_INDEX_LOG_2; i++) {
            if (executionBranch[i] != 0) return false;
        }
        return true;
    }

    function isValidMerkleBranch(
        bytes32 leaf,
        bytes32[] memory branch,
        uint64 depth,
        uint256 index,
        bytes32 root
    ) private pure returns (bool) {
        // Check if ``leaf`` at ``index`` verifies against the Merkle ``root`` and ``branch``.
        bytes32 value = leaf;
        for (uint64 i = 0; i < depth; i++) {
            if (((index / (2**i)) % 2) != 0) {
                value = sha256(abi.encodePacked(branch[i], value));
            } else {
                value = sha256(abi.encodePacked(value, branch[i]));
            }
        }

        return value == root;
    }

    function isValidLightClientHeader(Structs.LightClientHeader memory header)
        private
        view
        returns (bool)
    {
        uint64 epoch = Utils.computeEpochAtSlot(header.beacon.slot);

        if (epoch < CAPELLA_FORK_EPOCH) {
            return (isEmptyExecutionPayloadHeader(header.execution) &&
                isEmptyExecutionBranch(header.executionBranch));
        }

        return
            isValidMerkleBranch(
                merkleize.hashTreeRoot(header.execution), // was getLcExecutionRoot
                header.executionBranch,
                EXECUTION_PAYLOAD_INDEX_LOG_2,
                getSubtreeIndex(EXECUTION_PAYLOAD_INDEX),
                header.beacon.bodyRoot
            );
    }

    function initializeLightClientStore(
        Structs.LightClientBootstrap memory bootstrap,
        bytes32 trustedBlockRoot
    ) external {
        // Validate bootstrap
        require(isValidLightClientHeader(bootstrap.header));

        require(merkleize.hashTreeRoot(bootstrap.header.beacon) == trustedBlockRoot);

        require(
            isValidMerkleBranch(
                merkleize.hashTreeRoot(bootstrap.currentSyncCommittee),
                bootstrap.currentSyncCommitteeBranch,
                CURRENT_SYNC_COMMITTEE_INDEX_LOG_2,
                getSubtreeIndex(CURRENT_SYNC_COMMITTEE_INDEX),
                bootstrap.header.beacon.stateRoot
            )
        );

        // Initialize store
        store.finalizedHeader = bootstrap.header;
        store.currentSyncCommittee = bootstrap.currentSyncCommittee;
        store.optimisticHeader = bootstrap.header;
    }

    // Not sure if this check is correct. There is for sure a better way to do this
    function isNextSyncCommitteeKnown() private view returns (bool) {
        Structs.SyncCommittee memory emptySyncCommittee;
        return
            keccak256(store.nextSyncCommittee.aggregatePubkey) !=
            keccak256(emptySyncCommittee.aggregatePubkey);
        //return keccak256(abi.encode(store.nextSyncCommittee.pubkeys)) != keccak256(abi.encode(emptySyncCommittee.pubkeys));
    }

    // Not sure if it is correct
    function isSyncCommitteeUpdate(Structs.LightClientUpdate memory update)
        private
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < NEXT_SYNC_COMMITTEE_INDEX_LOG_2; i++) {
            if (update.nextSyncCommitteeBranch[i] != bytes32(0)) {
                return true;
            }
        }
        return false;
    }

    function isFinalityUpdate(Structs.LightClientUpdate memory update)
        private
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < FINALIZED_ROOT_INDEX_LOG_2; i++) {
            if (update.finalityBranch[i] != bytes32(0)) {
                return true;
            }
        }
        return false;
    }

    function computeForkVersion(uint256 epoch) private pure returns (bytes4) {
        if (epoch >= CAPELLA_FORK_EPOCH) return CAPELLA_FORK_VERSION;
        if (epoch >= BELLATRIX_FORK_EPOCH) return BELLATRIX_FORK_VERSION;
        if (epoch >= ALTAIR_FORK_EPOCH) return ALTAIR_FORK_VERSION;
        return GENESIS_FORK_VERSION;
    }

    function computeDomain(bytes4 forkVersion, bytes32 genesisValidatorsRoot)
        private
        view
        returns (bytes32)
    {
        //not sure
        bytes32[] memory chunks = new bytes32[](2);
        chunks[0] = bytes32(abi.encodePacked(forkVersion, bytes28(0)));
        chunks[1] = genesisValidatorsRoot;
        bytes32 forkDataRoot = merkleize.merkleize_chunks(chunks, 2);

        // not sure
        bytes memory domain = new bytes(32);
        domain[0] = DOMAIN_SYNC_COMMITTEE[0];
        domain[0] = DOMAIN_SYNC_COMMITTEE[1];
        domain[0] = DOMAIN_SYNC_COMMITTEE[2];
        domain[0] = DOMAIN_SYNC_COMMITTEE[3];
        for (uint256 i = 4; i < 32; i++) {
            domain[i] = forkDataRoot[i];
        }
        return bytes32(domain);
    }

    function computeSigningRoot(
        Structs.BeaconBlockHeader memory beacon,
        bytes32 domain
    ) private view returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](2);
        chunks[0] = merkleize.hashTreeRoot(beacon);
        chunks[1] = domain;

        return merkleize.merkleize_chunks(chunks, 2);
    }

    function validateLightClientUpdate(
        Structs.LightClientUpdate memory update,
        uint64 currentSlot,
        bytes32 genesisValidatorsRoot
    ) private view {
        uint256 syncCommitteeParticipants;
        for (
            uint256 i = 0;
            i < update.syncAggregate.syncCommitteeBits.length;
            i++
        ) {
            if (update.syncAggregate.syncCommitteeBits[i]) {
                syncCommitteeParticipants++;
            }
        }
        require(syncCommitteeParticipants >= MIN_SYNC_COMMITTEE_PARTICIPANTS);

        require(isValidLightClientHeader(update.attestedHeader));

        require(currentSlot >= update.signatureSlot);
        require(update.signatureSlot > update.attestedHeader.beacon.slot);
        require(
            update.attestedHeader.beacon.slot >=
                update.finalizedHeader.beacon.slot
        );

        uint64 storePeriod = Utils.computeSyncCommitteePeriodAtSlot(
            store.finalizedHeader.beacon.slot
        );
        uint64 updateSignaturePeriod = Utils.computeSyncCommitteePeriodAtSlot(
            update.signatureSlot
        );

        if (isNextSyncCommitteeKnown()) {
            require(
                (updateSignaturePeriod == storePeriod) ||
                    (updateSignaturePeriod == storePeriod + 1)
            );
        } else {
            require(updateSignaturePeriod == storePeriod);
        }

        uint64 updateAttestedPeriod = Utils.computeSyncCommitteePeriodAtSlot(
            update.attestedHeader.beacon.slot
        );
        bool updateHasNextSyncCommittee = (!isNextSyncCommitteeKnown()) &&
            (isSyncCommitteeUpdate(update) &&
                (updateAttestedPeriod == storePeriod));

        require(
            (update.attestedHeader.beacon.slot >
                store.finalizedHeader.beacon.slot) || updateHasNextSyncCommittee
        );

        if (!isFinalityUpdate(update)) {
            // The finalized header must be empty
            require(update.finalizedHeader.beacon.bodyRoot == bytes32(0));
        } else {
            bytes32 finalizedRoot;
            if (update.finalizedHeader.beacon.slot == GENESIS_SLOT) {
                require(update.finalizedHeader.beacon.bodyRoot == bytes32(0));
            } else {
                require(isValidLightClientHeader(update.finalizedHeader));
                finalizedRoot = merkleize.hashTreeRoot(update.finalizedHeader.beacon);
            }
            require(
                isValidMerkleBranch(
                    finalizedRoot,
                    update.finalityBranch,
                    FINALIZED_ROOT_INDEX_LOG_2,
                    getSubtreeIndex(FINALIZED_ROOT_INDEX),
                    update.attestedHeader.beacon.stateRoot
                )
            );
        }

        if (!isSyncCommitteeUpdate(update)) {
            Structs.SyncCommittee memory emptySyncCommittee;
            // This can be improved
            require(
                keccak256(update.nextSyncCommittee.aggregatePubkey) !=
                    keccak256(emptySyncCommittee.aggregatePubkey)
            );
        } else {
            if (
                updateAttestedPeriod == storePeriod &&
                isNextSyncCommitteeKnown()
            ) {
                // This can be improved
                require(
                    keccak256(update.nextSyncCommittee.aggregatePubkey) !=
                        keccak256(store.nextSyncCommittee.aggregatePubkey)
                );
            }
            require(
                isValidMerkleBranch(
                    merkleize.hashTreeRoot(update.nextSyncCommittee),
                    update.nextSyncCommitteeBranch,
                    NEXT_SYNC_COMMITTEE_INDEX_LOG_2,
                    getSubtreeIndex(NEXT_SYNC_COMMITTEE_INDEX),
                    update.attestedHeader.beacon.stateRoot
                )
            );
        }

        Structs.SyncCommittee memory syncCommittee;
        if (updateSignaturePeriod == storePeriod) {
            syncCommittee = store.currentSyncCommittee;
        } else {
            syncCommittee = store.nextSyncCommittee;
        }

        bytes[] memory participantPubkeys = new bytes[](
            syncCommitteeParticipants
        );
        uint256 j;
        for (uint256 i = 0; i < SYNC_COMMITTEE_SIZE; i++) {
            if (update.syncAggregate.syncCommitteeBits[i]) {
                participantPubkeys[j] = (syncCommittee.pubkeys[i]);
                j++;
            }
        }

        uint64 forkVersionSlot = (
            update.signatureSlot > 1 ? update.signatureSlot : 1
        ) - 1;
        bytes4 forkVersion = computeForkVersion(
            Utils.computeEpochAtSlot(forkVersionSlot)
        );
        bytes32 domain = computeDomain(forkVersion, genesisValidatorsRoot);

        bytes32 signingRoot = computeSigningRoot(
            update.attestedHeader.beacon,
            domain
        );

        // !! BLS signature verification, to implement
        //require(bls.fastAggregateVerify(participantPubkeys, signingRoot, update.syncAggregate.syncCommitteeSignature));
    }

    function isBetterUpdate(
        Structs.LightClientUpdate memory newUpdate,
        Structs.LightClientUpdate memory oldUpdate
    ) private pure returns (bool) {
        uint256 maxActiveParticipants = newUpdate.syncAggregate.syncCommitteeBits.length;
        
        uint256 newNumActiveParticipants;
        for (
            uint256 i = 0;
            i < newUpdate.syncAggregate.syncCommitteeBits.length;
            i++
        ) {
            if (newUpdate.syncAggregate.syncCommitteeBits[i]) {
                newNumActiveParticipants++;
            }
        }

        uint256 oldNumActiveParticipants;
        for (
            uint256 i = 0;
            i < oldUpdate.syncAggregate.syncCommitteeBits.length;
            i++
        ) {
            if (oldUpdate.syncAggregate.syncCommitteeBits[i]) {
                oldNumActiveParticipants++;
            }
        }

        bool newHasSupermajority = newNumActiveParticipants * 3 >= maxActiveParticipants * 2;
        bool oldHasSupermajority = oldNumActiveParticipants * 3 >= maxActiveParticipants * 2;

        if ( newHasSupermajority != oldHasSupermajority) {
            return newHasSupermajority && !oldHasSupermajority;
        }
        if(!newHasSupermajority && newNumActiveParticipants != oldNumActiveParticipants) {
            return newNumActiveParticipants > oldNumActiveParticipants;
        }

        bool newHasRelevantSyncCommittee = isSyncCommitteeUpdate(newUpdate) && (Utils.computeSyncCommitteePeriodAtSlot(newUpdate.attestedHeader.beacon.slot) == Utils.computeSyncCommitteePeriodAtSlot(newUpdate.signatureSlot));
        bool oldHasRelevantSyncCommittee = isSyncCommitteeUpdate(oldUpdate) && (Utils.computeSyncCommitteePeriodAtSlot(oldUpdate.attestedHeader.beacon.slot) == Utils.computeSyncCommitteePeriodAtSlot(oldUpdate.signatureSlot));

        if(newHasRelevantSyncCommittee != oldHasRelevantSyncCommittee) {
            return newHasRelevantSyncCommittee;
        }

        bool newHasFinality = isFinalityUpdate(newUpdate);
        bool oldHasFinality = isFinalityUpdate(oldUpdate);

        if(newHasFinality != oldHasFinality) {
            return newHasFinality;
        }

        if ( newHasFinality ) {
            bool newHasSyncCommitteeFinality = (Utils.computeSyncCommitteePeriodAtSlot(newUpdate.finalizedHeader.beacon.slot) == Utils.computeSyncCommitteePeriodAtSlot(newUpdate.attestedHeader.beacon.slot));
            bool oldHasSyncCommitteeFinality = (Utils.computeSyncCommitteePeriodAtSlot(oldUpdate.finalizedHeader.beacon.slot) == Utils.computeSyncCommitteePeriodAtSlot(oldUpdate.attestedHeader.beacon.slot));
            if(newHasSyncCommitteeFinality != oldHasSyncCommitteeFinality) {
                return newHasSyncCommitteeFinality;
            }
        }

        if (newNumActiveParticipants != oldNumActiveParticipants) {
            return newNumActiveParticipants > oldNumActiveParticipants;
        }

        if(newUpdate.attestedHeader.beacon.slot != oldUpdate.attestedHeader.beacon.slot){
            return newUpdate.attestedHeader.beacon.slot < oldUpdate.attestedHeader.beacon.slot;
        }

        return newUpdate.signatureSlot < oldUpdate.signatureSlot;
    }

    function applyLightClientUpdate(
        Structs.LightClientUpdate memory update
    ) private {
        uint64 storePeriod = Utils.computeSyncCommitteePeriodAtSlot(store.finalizedHeader.beacon.slot);
        uint64 updateFinalizedPeriod = Utils.computeSyncCommitteePeriodAtSlot(update.finalizedHeader.beacon.slot);

        if(!isNextSyncCommitteeKnown()){
            require(updateFinalizedPeriod == storePeriod);
            store.nextSyncCommittee = update.nextSyncCommittee;
        } else if(updateFinalizedPeriod == storePeriod + 1) {
            store.currentSyncCommittee = store.nextSyncCommittee;
            store.nextSyncCommittee = update.nextSyncCommittee;
            store.previousMaxActiveParticipants = store.currentMaxActiveParticipants;
            store.currentMaxActiveParticipants = 0;
        }
        if(update.finalizedHeader.beacon.slot > store.finalizedHeader.beacon.slot) {
            store.finalizedHeader = update.finalizedHeader;
            if(store.finalizedHeader.beacon.slot > store.optimisticHeader.beacon.slot) {
                store.optimisticHeader = store.finalizedHeader;
            }
        }
    }

    function processLightClientUpdate(
        Structs.LightClientUpdate memory update,
        uint64 currentSlot,
        bytes32 genesisValidatorsRoot
    ) external {
        validateLightClientUpdate(update, currentSlot, genesisValidatorsRoot);
        
        bool[SYNC_COMMITTEE_SIZE] memory syncCommitteeBits = update
            .syncAggregate
            .syncCommitteeBits;

        if (
            store.bestValidUpdate.attestedHeader.beacon.bodyRoot !=
            bytes32(0) ||
            isBetterUpdate(update, store.bestValidUpdate)
        ) {
            store.bestValidUpdate = update;
        }

        uint64 currentParticipants;
        for (
            uint256 i = 0;
            i < SYNC_COMMITTEE_SIZE;
            i++
        ) {
            if (syncCommitteeBits[i]) {
                currentParticipants++;
            }
        }

        store.currentMaxActiveParticipants = (store.currentMaxActiveParticipants > currentParticipants ? store.currentMaxActiveParticipants : currentParticipants);

        uint64 safetyThreshold = (store.previousMaxActiveParticipants > store.currentMaxActiveParticipants ? store.previousMaxActiveParticipants : store.currentMaxActiveParticipants) / 2;
        
        if(currentParticipants > safetyThreshold && update.attestedHeader.beacon.slot > store.optimisticHeader.beacon.slot) {
            store.optimisticHeader = update.attestedHeader;
        }

        bool updateHasFinalizedNextSyncCommittee = (
            !isNextSyncCommitteeKnown() &&
            isSyncCommitteeUpdate(update) &&
            isFinalityUpdate(update) &&
            (Utils.computeSyncCommitteePeriodAtSlot(update.finalizedHeader.beacon.slot) == Utils.computeSyncCommitteePeriodAtSlot(update.attestedHeader.beacon.slot))
        );

        if (
            currentParticipants * 3 >= SYNC_COMMITTEE_SIZE * 2 &&
            (
                update.finalizedHeader.beacon.slot > store.finalizedHeader.beacon.slot ||
                updateHasFinalizedNextSyncCommittee
            )
        ) {
            applyLightClientUpdate(update);
            Structs.LightClientUpdate memory emptyLightClientUpdate;
            store.bestValidUpdate = emptyLightClientUpdate;
        }
    }
}