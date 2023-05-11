pragma solidity ^0.8.17;

contract LightClient {
    uint8 constant CURRENT_SYNC_COMMITTEE_INDEX = 54;
    uint8 constant CURRENT_SYNC_COMMITTEE_INDEX_LOG_2 = 5;
    uint256 constant EXECUTION_PAYLOAD_INDEX = 25;
    uint8 constant EXECUTION_PAYLOAD_INDEX_LOG_2 = 4;
    uint16 constant SYNC_COMMITTEE_SIZE = 512;
    uint16 constant BYTES_PER_LOGS_BLOOM = 256;
    uint8 constant SLOTS_PER_EPOCH = 32;
    uint32 constant CAPELLA_FORK_EPOCH = 194048;
    uint256 constant NEXT_SYNC_COMMITTEE_INDEX_LOG_2 = 5;
    uint256 constant FINALIZED_ROOT_INDEX_LOG_2 = 6;

    LightClientStore store;

    struct LightClientStore {
        LightClientHeader finalizedHeader;
        SyncCommittee currentSyncCommittee;
        SyncCommittee nextSyncCommittee;
        LightClientUpdate bestValidUpdate;
        LightClientHeader optimisticHeader;
        uint64 previousMaxActiveParticipants;
        uint64 currentMaxActiveParticipants;
    }

    struct LightClientUpdate {
        LightClientHeader attestedHeader;
        SyncCommittee nextSyncCommittee;
        bytes32[NEXT_SYNC_COMMITTEE_INDEX_LOG_2] nextSyncCommitteeBranch;
        LightClientHeader finalizedHeader;
        bytes32[FINALIZED_ROOT_INDEX_LOG_2] finalityBranch;
        SyncAggregate syncAggregate;
        uint64 signatureSlot;
    }

    struct SyncAggregate {
        bool[SYNC_COMMITTEE_SIZE] syncCommitteeBits;
        bytes32[3] syncCommitteeSignature; // should be bytes96
    }

    struct BeaconBlockHeader {
        uint64 slot;
        uint64 proposerIndex;
        bytes32 parentRoot;
        bytes32 stateRoot;
        bytes32 bodyRoot;
    }

    struct ExecutionPayloadHeader {
        bytes32 parentHash;
        bytes20 feeRecipient;
        bytes32 stateRoot;
        bytes32 receiptsRoot;
        bytes1[BYTES_PER_LOGS_BLOOM] logsBloom;
        bytes32 prevRandao;
        uint64 blockNumber;
        uint64 gasLimit;
        uint64 gasUsed;
        uint64 timestamp;
        bytes1[] extraData;
        uint256 baseFeePerGas;
        bytes32 blockHash;
        bytes32 transactionsRoot;
        bytes32 withdrawalsRoot;
    }

    struct LightClientHeader {
        BeaconBlockHeader beacon;
        ExecutionPayloadHeader execution;
        bytes32[] executionBranch; // should be fixed to EXECUTION_PAYLOAD_INDEX_LOG_2
    }

    struct SyncCommittee {
        bytes32[SYNC_COMMITTEE_SIZE][2] pubkeys; // should be bytes48
        bytes32[2] aggregatePubkey; // should be bytes48
    }

    struct LightClientBootstrap {
        LightClientHeader header;
        SyncCommittee currentSyncCommittee;
        bytes32[] currentSyncCommitteeBranch; // should be fixed to CURRENT_SYNC_COMMITTEE_INDEX_LOG_2
    }

    function computeEpochAtSlot(uint64 slot) private pure returns (uint64) {
        return slot / SLOTS_PER_EPOCH;
    }

    function isValidMerkleBranch(
        bytes32 leaf,
        bytes32[] memory branch,
        uint64 depth,
        uint256 index,
        bytes32 root
    ) private pure returns (bool) {
        bytes32 value = leaf;
        for (uint64 i = 0; i < depth; i++) {
            if (((index / (2**i)) % 2) != 0) {
                value = sha256(concat(branch[i], value));
            } else {
                value = sha256(concat(value, branch[i]));
            }
        }
        return value == root;
    }

    // taken from https://medium.com/coinmonks/math-in-solidity-part-5-exponent-and-logarithm-9aef8515136e
    function log2(uint256 x) private pure returns (uint256 n) {
        if (x >= 2**128) {
            x >>= 128;
            n += 128;
        }
        if (x >= 2**64) {
            x >>= 64;
            n += 64;
        }
        if (x >= 2**32) {
            x >>= 32;
            n += 32;
        }
        if (x >= 2**16) {
            x >>= 16;
            n += 16;
        }
        if (x >= 2**8) {
            x >>= 8;
            n += 8;
        }
        if (x >= 2**4) {
            x >>= 4;
            n += 4;
        }
        if (x >= 2**2) {
            x >>= 2;
            n += 2;
        }
        if (x >= 2**1) {
            n += 1;
        }
    }

    function getSubtreeIndex(uint256 generalizedIndex)
        private
        pure
        returns (uint256)
    {
        return (generalizedIndex % (2**(log2(generalizedIndex))));
    }

    function isEmptyExecutionPayloadHeader(ExecutionPayloadHeader memory header)
        private
        pure
        returns (bool)
    {
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

    function isValidLightCLientHeader(LightClientHeader memory header)
        private
        pure
        returns (bool)
    {
        uint64 epoch = computeEpochAtSlot(header.beacon.slot);

        if (epoch < CAPELLA_FORK_EPOCH) {
            return (isEmptyExecutionPayloadHeader(header.execution) &&
                isEmptyExecutionBranch(header.executionBranch));
        }

        return
            isValidMerkleBranch(
                header.execution.blockHash, // was getLcExecutionRoot
                header.executionBranch,
                EXECUTION_PAYLOAD_INDEX_LOG_2,
                getSubtreeIndex(EXECUTION_PAYLOAD_INDEX),
                header.beacon.bodyRoot
            );
    }

    function hashTreeRoot(uint64 element) private view returns (bytes32) {}

    bytes32[100] zeroHashes;

    function concat(bytes32 b1, bytes32 b2)
        private
        pure
        returns (bytes memory)
    {
        bytes memory result = new bytes(64);
        assembly {
            mstore(add(result, 32), b1)
            mstore(add(result, 64), b2)
        }
        return result;
    }

    function initZeroHashes() private {
        for (uint256 layer = 1; layer < 100; layer++) {
            zeroHashes[layer] = sha256(
                concat(zeroHashes[layer - 1], zeroHashes[layer - 1])
            );
        }
    }

    function _merge_merkleize(
        bytes32 h,
        uint256 i,
        uint256 count,
        uint256 depth,
        bytes32[] memory tmp
    ) private view returns (uint256, bytes32) {
        uint256 j;
        while (true) {
            if (i & (1 << j) == 0) {
                if (i == count && j < depth) {
                    h = sha256(concat(h, zeroHashes[j]));
                } else {
                    break;
                }
            } else {
                h = sha256(concat(tmp[j], h));
            }
            j += 1;
        }
        return (j, h);
    }

    // Adapted from https://github.com/ethereum/consensus-specs/blob/v1.3.0/tests/core/pyspec/eth2spec/utils/merkle_minimal.py#L7
    function merkleize(bytes32[] memory chunks) private view returns (bytes32) {
        uint256 count = chunks.length;
        if (count == 0) {
            return zeroHashes[0];
        }

        uint256 depth = log2(count - 1);
        bytes32[] memory tmp = new bytes32[](depth);

        for (uint256 i = 0; i < count; i++) {
            uint256 j;
            bytes32 h;
            (j, h) = _merge_merkleize(chunks[i], i, count, depth, tmp);
            tmp[j] = h;
        }

        if (1 << depth != count) {
            uint256 j;
            bytes32 h;
            (j, h) = _merge_merkleize(zeroHashes[0], count, count, depth, tmp);
            tmp[j] = h;
        }

        return tmp[depth];
    }

    function toBytes(uint64 x) private pure returns (bytes32 b) {
        assembly {
            mstore(add(b, 32), x)
        }
    }

    // https://eth2book.info/capella/part2/building_blocks/merkleization/
    function hashTreeRoot(BeaconBlockHeader memory header)
        private
        view
        returns (bytes32)
    {
        bytes32[] memory chunks = new bytes32[](5);
        chunks[0] = toBytes(header.slot);
        chunks[1] = toBytes(header.proposerIndex);
        chunks[2] = header.parentRoot;
        chunks[3] = header.stateRoot;
        chunks[4] = header.bodyRoot;

        return merkleize(chunks);
    }

    function hashTreeRoot(bytes32[SYNC_COMMITTEE_SIZE][2] memory pubkeys)
        private
        view
        returns (bytes32)
    {
        bytes32[] memory chunks = new bytes32[](SYNC_COMMITTEE_SIZE);
        for (uint256 i = 0; i < SYNC_COMMITTEE_SIZE; i++) {
            chunks[i] = sha256(concat(pubkeys[i][0], pubkeys[i][1]));
        }

        return merkleize(chunks);
    }

    function hashTreeRoot(SyncCommittee memory syncCommittee)
        private
        view
        returns (bytes32)
    {
        bytes32[] memory chunks = new bytes32[](2);
        chunks[0] = hashTreeRoot(syncCommittee.pubkeys);
        chunks[1] = sha256(
            concat(
                syncCommittee.aggregatePubkey[0],
                syncCommittee.aggregatePubkey[1]
            )
        );

        return merkleize(chunks);
    }

    function initializeLightClientStore(
        bytes32 trustedBlockRoot,
        LightClientBootstrap memory bootstrap
    ) public {
        require(isValidLightCLientHeader(bootstrap.header));

        require(hashTreeRoot(bootstrap.header.beacon) == trustedBlockRoot);

        require(
            isValidMerkleBranch(
                hashTreeRoot(bootstrap.currentSyncCommittee),
                bootstrap.currentSyncCommitteeBranch,
                CURRENT_SYNC_COMMITTEE_INDEX_LOG_2,
                getSubtreeIndex(CURRENT_SYNC_COMMITTEE_INDEX),
                bootstrap.header.beacon.stateRoot
            )
        );

        store.finalizedHeader = bootstrap.header;
        store.currentSyncCommittee = bootstrap.currentSyncCommittee;
        store.optimisticHeader = bootstrap.header;
    }
}
