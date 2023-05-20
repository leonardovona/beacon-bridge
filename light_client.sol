pragma solidity ^0.8.17;

import "hardhat/console.sol";

contract LightClient {
    // Constants
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

    // Attributes
    LightClientStore store;
    bytes32[100] zeroHashes;

    //Types definition
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
        bytes logsBloom; // BYTES_PER_LOGS_BLOOM len
        bytes32 prevRandao;
        uint64 blockNumber;
        uint64 gasLimit;
        uint64 gasUsed;
        uint64 timestamp;
        bytes extraData;
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
        bytes[SYNC_COMMITTEE_SIZE] pubkeys; // should be bytes48
        bytes aggregatePubkey; // should be bytes48
    }

    struct LightClientBootstrap {
        LightClientHeader header;
        SyncCommittee currentSyncCommittee;
        bytes32[] currentSyncCommitteeBranch; // should be fixed to CURRENT_SYNC_COMMITTEE_INDEX_LOG_2
    }

    // Clock utilities
    function computeEpochAtSlot(uint64 slot) private pure returns (uint64) {
        return slot / SLOTS_PER_EPOCH;
    }

    // Math utilities
     // Computes ceil(log2(x))
    // taken from https://medium.com/coinmonks/math-in-solidity-part-5-exponent-and-logarithm-9aef8515136e
    function floorLog2(uint256 x) private pure returns (uint256 n) {
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

    // Computes ceil(log2(x))
    // taken from https://medium.com/coinmonks/math-in-solidity-part-5-exponent-and-logarithm-9aef8515136e
    function ceilLog2(uint256 x) private pure returns (uint256 n) {
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
            x >>= 1;
            n += 1;
        }
        if (x >= 2**0) {
            n += 1;
        }
    }

    // Concatenate two bytes32 into a single bytes64
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

    // Initialization
    function initZeroHashes() private {
        for (uint256 layer = 1; layer < 100; layer++) {
            zeroHashes[layer] = sha256(
                concat(zeroHashes[layer - 1], zeroHashes[layer - 1])
            );
        }
    }

    constructor() {
        initZeroHashes();
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

    function getSubtreeIndex(uint256 generalizedIndex)
        private
        pure
        returns (uint256)
    {
        return (generalizedIndex % (2**(floorLog2(generalizedIndex))));
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

    function isValidLightClientHeader(LightClientHeader memory header)
        private
        view
        returns (bool)
    {
        uint64 epoch = computeEpochAtSlot(header.beacon.slot);

        if (epoch < CAPELLA_FORK_EPOCH) {
            return (isEmptyExecutionPayloadHeader(header.execution) &&
                isEmptyExecutionBranch(header.executionBranch));
        }

        return
            isValidMerkleBranch(
                hashTreeRoot(header.execution), // was getLcExecutionRoot
                header.executionBranch,
                EXECUTION_PAYLOAD_INDEX_LOG_2,
                getSubtreeIndex(EXECUTION_PAYLOAD_INDEX),
                header.beacon.bodyRoot
            );
    }


    function merge(
        bytes32 h,
        uint i,
        uint count,
        uint depth,
        bytes32[] memory tmp
    ) private view {
        uint j = 0;
        while(true){
            if (i & (1 << j) == 0){
                if (i == count && j < depth){
                    h = sha256(abi.encodePacked(h, zeroHashes[j]));
                } else {
                    break;
                }
            } else {
                h = sha256(abi.encodePacked(tmp[j], h));
            }
            j++;
        }

        // if (j > depth) {
        //      j = depth;
        // }
        tmp[j] = h;
    }

    function merkleize(
        bytes32[] memory chunks,
        uint limit
    ) private view returns ( bytes32 ) {
        uint count = chunks.length;

        // if(count > limit) raise exception

        if(limit == 0) {
            return zeroHashes[0];
        }


        uint depth = ceilLog2(count - 1);


        if(depth == 0) depth = 1;

        uint max_depth = ceilLog2(limit - 1);

        bytes32[] memory tmp = new bytes32[](max_depth + 1);

        for(uint i = 0; i < count; i++) {
            merge(chunks[i], i, count, depth, tmp);
        }

        if(1 << depth != count) {
            merge(zeroHashes[0], count, count, depth, tmp);
        }

        for(uint j = depth; j < max_depth; j++){
            tmp[j + 1] = sha256(abi.encodePacked(tmp[j], zeroHashes[j]));
        }

        return tmp[max_depth];
    }

    // function _merge_merkleize(
    //     bytes32 h,
    //     uint256 i,
    //     uint256 count,
    //     uint256 depth,
    //     bytes32[] memory tmp
    // ) private view returns (uint256, bytes32) {
    //     uint256 j;
    //     console.log("h");
    //     console.logBytes32(h);
    //     console.log("i", i);
    //     console.log("count", count);
    //     console.log("depth", depth);
    //     while (true) {
    //         if (i & (1 << j) == 0) {
    //             if ((i == count) && (j < depth)) {
    //                 // If the number of chunks is not a power of two, pad with hash roots of empty trees
    //                 h = sha256(concat(h, zeroHashes[j]));
    //             } else {
    //                 break;
    //             }
    //         } else {
    //             h = sha256(concat(tmp[j], h));
    //         }
    //         j += 1;
    //     }

    //     // Added this check
    //     if (j > depth) {
    //         j = depth;
    //     }
    //     return (j, h);
    // }

    // // Adapted from https://github.com/ethereum/consensus-specs/blob/v1.3.0/tests/core/pyspec/eth2spec/utils/merkle_minimal.py#L7
    // function merkleize(bytes32[] memory chunks) private view returns (bytes32) {
    //     uint256 count = chunks.length;
    //     if (count == 0) {
    //         return zeroHashes[0];
    //     }

    //     uint256 depth = log2(count - 1);

    //     // if (depth == 0) {
    //     //    depth++;
    //     // }

    //     bytes32[] memory tmp = new bytes32[](depth + 1);

    //     // Build the tree by merging leaf by leaf
    //     for (uint256 i = 0; i < count; i++) {
    //         uint256 j;
    //         bytes32 h;
    //         (j, h) = _merge_merkleize(chunks[i], i, count, depth, tmp);
    //         tmp[j] = h;
    //         console.log("tmp[j]");
    //         console.logBytes32(tmp[j]);
    //     }

    //     if (1 << depth != count) {
    //         console.log(count, " ", 1 << depth);
    //         uint256 j;
    //         bytes32 h;
    //         (j, h) = _merge_merkleize(zeroHashes[0], count, count, depth, tmp);
    //         tmp[j] = h;
    //         console.log("tmp[j]");
    //         console.logBytes32(tmp[j]);
    //     }
    //     return tmp[depth];
    // }

    // https://ethereum.stackexchange.com/questions/83626/how-to-reverse-byte-order-in-uint256-or-bytes32
    function reverse(uint256 input) private pure returns (uint256 v) {
        v = input;

        // swap bytes
        v =
            ((v &
                0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >>
                8) |
            ((v &
                0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) <<
                8);

        // swap 2-byte long pairs
        v =
            ((v &
                0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >>
                16) |
            ((v &
                0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) <<
                16);

        // swap 4-byte long pairs
        v =
            ((v &
                0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >>
                32) |
            ((v &
                0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) <<
                32);

        // swap 8-byte long pairs
        v =
            ((v &
                0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >>
                64) |
            ((v &
                0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) <<
                64);

        // swap 16-byte long pairs
        v = (v >> 128) | (v << 128);
    }

    function toBytes(uint64 a) private pure returns (bytes32) {
        return bytes32(reverse(uint256(a)));
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

        return merkleize(chunks, 5);
    }

    /*function hashTreeRoot(bytes memory pubkey) private pure returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](2);

        bytes32 temp;
        assembly {
            temp := mload(add(pubkey, 32))
        }
        chunks[0] = temp;
        assembly {
            temp := mload(add(pubkey, 64))
        }
        chunks[1] = temp;

        return sha256(concat(chunks[0], chunks[1]));
    }*/

    function hashTreeRoot(bytes[SYNC_COMMITTEE_SIZE] memory pubkeys)
        private
        view
        returns (bytes32)
    {
        bytes32[] memory chunks = new bytes32[](SYNC_COMMITTEE_SIZE);
        for (uint256 i = 0; i < SYNC_COMMITTEE_SIZE; i++) {
            chunks[i] = sha256(abi.encodePacked(pubkeys[i], bytes16(0)));
        }

        //return chunks[0];
        return merkleize(chunks, SYNC_COMMITTEE_SIZE);
    }

    function hashTreeRoot(SyncCommittee memory syncCommittee)
        private
        view
        returns (bytes32)
    {
        bytes32[] memory chunks = new bytes32[](2);
        chunks[0] = hashTreeRoot(syncCommittee.pubkeys);
        chunks[1] = sha256(abi.encodePacked(syncCommittee.aggregatePubkey, bytes16(0)));
        /*chunks[1] = sha256(
            concat(
                syncCommittee.aggregatePubkey[0],
                syncCommittee.aggregatePubkey[1]
            )
        );*/

        return merkleize(chunks, 2);
    }

    /*
    struct BeaconBlockHeader {
        uint64 slot;
        uint64 proposerIndex;
        bytes32 parentRoot;
        bytes32 stateRoot;
        bytes32 bodyRoot;
    }

    struct ExecutionPayloadHeader {

        bytes logsBloom; // BYTES_PER_LOGS_BLOOM len
        bytes32 prevRandao;
        uint64 blockNumber;
        uint64 gasLimit;
        uint64 gasUsed;
        uint64 timestamp;
        bytes extraData;
        uint256 baseFeePerGas;
        bytes32 blockHash;
        bytes32 transactionsRoot;
        bytes32 withdrawalsRoot;
    }
    */


    function hashTreeRoot(ExecutionPayloadHeader memory header) 
        private 
        view
        returns ( bytes32 ) {

        bytes32[] memory chunks = new bytes32[](15);
        chunks[0] = header.parentHash;
        chunks[1] = bytes32(abi.encodePacked(header.feeRecipient, bytes12(0))); //not sure
        chunks[2] = header.stateRoot;
        chunks[3] = header.receiptsRoot;

        bytes32[] memory chunksLogsBloom = new bytes32[](256 / 32);
        for(uint i = 0; i < (256 / 32); i++){
            bytes memory temp = new bytes(32);
            for(uint j = 0; j < 32; j++) {
                temp[j] = header.logsBloom[i*32 + j];
            }
            chunksLogsBloom[i] = bytes32(temp); 
        }
        chunks[4] = merkleize(chunksLogsBloom, 256 / 32);
        
        chunks[5] = header.prevRandao;
        chunks[6] = toBytes(header.blockNumber);
        chunks[7] = toBytes(header.gasLimit);
        chunks[8] = toBytes(header.gasUsed);
        chunks[9] = toBytes(header.timestamp);

        bytes32[] memory chunksExtraData = new bytes32[](2);
        chunksExtraData[0] = bytes32(abi.encodePacked(header.extraData, new bytes(32 - header.extraData.length)));
        chunksExtraData[1] = bytes32(reverse(header.extraData.length));
        chunks[10] = merkleize(chunksExtraData, 2);

        chunks[11] = bytes32(reverse(header.baseFeePerGas));
        chunks[12] = header.blockHash;
        chunks[13] = header.transactionsRoot;
        chunks[14] = header.withdrawalsRoot;

        return merkleize(chunks, 15);
    }

    //bytes32 bytes_slot;

    /*function testHashTreeRootSyncCommittee(
        bytes[SYNC_COMMITTEE_SIZE] memory pubkeys
    ) external view {
        
        bytes32[] memory chunks = new bytes32[](SYNC_COMMITTEE_SIZE);
        for(uint i = 0; i < SYNC_COMMITTEE_SIZE; i++) {
            chunks[i] = sha256(abi.encodePacked(pubkeys[i], bytes16(0)));
        }

        //return chunks[0];

        console.logBytes32(merkleize(chunks, SYNC_COMMITTEE_SIZE));
    }*/

    /*

    struct LightClientHeader {
        BeaconBlockHeader beacon;
        ExecutionPayloadHeader execution;
        bytes32[] executionBranch; // should be fixed to EXECUTION_PAYLOAD_INDEX_LOG_2
    
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
    */

    function testIsValidLightClientHeader(
        //LightClientHeader
        //BeaconBlockHeader
        BeaconBlockHeader memory beacon,
        //ExecutionPayloadHeader
        ExecutionPayloadHeader memory execution,
        //executionBranch
        bytes32[] memory executionBranch
    ) external view {
        LightClientHeader memory header;
        header.beacon = beacon;
        header.execution = execution;
        header.executionBranch = executionBranch;
        require(isValidLightClientHeader(header));
    }

    function testTrustedBlockRoot(
        bytes32 trustedBlockRoot,
        BeaconBlockHeader memory beacon
    ) external view {
        require(hashTreeRoot(beacon) == trustedBlockRoot);
    }

    function testIsValidMerkleBranch(
        bytes[SYNC_COMMITTEE_SIZE] memory pubkeys,
        bytes memory aggregatePubkey,
        bytes32[] memory currentSyncCommitteeBranch,
        bytes32 stateRoot
    ) external view {
        SyncCommittee memory currentSyncCommittee;

        currentSyncCommittee.pubkeys = pubkeys;
        currentSyncCommittee.aggregatePubkey = aggregatePubkey;

        require(
            isValidMerkleBranch(
                hashTreeRoot(currentSyncCommittee),
                currentSyncCommitteeBranch,
                CURRENT_SYNC_COMMITTEE_INDEX_LOG_2,
                getSubtreeIndex(CURRENT_SYNC_COMMITTEE_INDEX),
                stateRoot
            )
        );
    }

    function initializeLightClientStore_small(
        bytes[SYNC_COMMITTEE_SIZE] memory currentSyncCommitteePubKeys,
        bytes memory currentSyncCommitteeAggregate,
        bytes32[] memory currentSyncCommitteeBranch,
        bytes32 stateRoot //bytes32 trustedBlockRoot, //BeaconBlockHeader memory bbh
    ) external view {

        //require(isValidLightClientHeader(bootstrap.header));

/*
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
*/

//

        //require(hashTreeRoot(bbh) == trustedBlockRoot);
        // SyncCommittee memory currentSyncCommittee;
        // currentSyncCommittee.pubkeys = currentSyncCommitteePubKeys;
        // currentSyncCommittee.aggregatePubkey = currentSyncCommitteeAggregate;


        // console.logBytes32(hashTreeRoot(currentSyncCommitteePubKeys));
        //console.logBytes32(hashTreeRoot(currentSyncCommitteePubKeys[0]));
        /*
        bytes memory temp = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            temp[i] = currentSyncCommitteePubKeys[0][i];
        }
        bytes memory temp2 = new bytes(32);
        for (uint256 j = 0; j < 16; j++) {
            temp2[j] = currentSyncCommitteePubKeys[0][j + 32];
        }
        console.logBytes(currentSyncCommitteePubKeys[0]);
        console.logBytes(temp);
        console.logBytes(temp2);

        bytes32[] memory chunks = new bytes32[](2);
        chunks[0] = temp;
        chunks[1] = temp2;
        merkleize(chunks);
        
        console.logBytes32(sha256(currentSyncCommitteePubKeys[0]));
        */
        /*
        console.log(
            isValidMerkleBranch(
                hashTreeRoot(currentSyncCommittee),
                currentSyncCommitteeBranch,
                CURRENT_SYNC_COMMITTEE_INDEX_LOG_2,
                getSubtreeIndex(CURRENT_SYNC_COMMITTEE_INDEX),
                stateRoot
            )
        );*/

        //require(
        //    isValidMerkleBranch(
        //        hashTreeRoot(currentSyncCommittee),
        //        currentSyncCommitteeBranch,
        //        CURRENT_SYNC_COMMITTEE_INDEX_LOG_2,
        //        getSubtreeIndex(CURRENT_SYNC_COMMITTEE_INDEX),
        //        stateRoot
        //    )
        //);
    }

    function testInitializeLightClientStore(
        //LightClientHeader
        //BeaconBlockHeader
        BeaconBlockHeader memory beacon,
        //ExecutionPayloadHeader
        ExecutionPayloadHeader memory execution,
        //ExecutionBranch
        bytes32[] memory executionBranch,
        //
        bytes32 trustedBlockRoot,
        //
        //CurrentSyncCommittee
        bytes[SYNC_COMMITTEE_SIZE] memory pubkeys,
        bytes memory aggregatePubkey,
        //
        bytes32[] memory currentSyncCommitteeBranch
    ) external {
        LightClientHeader memory header;
        header.beacon = beacon;
        header.execution = execution;
        header.executionBranch = executionBranch;

        SyncCommittee memory currentSyncCommittee;
        currentSyncCommittee.pubkeys = pubkeys;
        currentSyncCommittee.aggregatePubkey = aggregatePubkey;

        require(isValidLightClientHeader(header));

        require(hashTreeRoot(beacon) == trustedBlockRoot);

        require(
            isValidMerkleBranch(
                hashTreeRoot(currentSyncCommittee),
                currentSyncCommitteeBranch,
                CURRENT_SYNC_COMMITTEE_INDEX_LOG_2,
                getSubtreeIndex(CURRENT_SYNC_COMMITTEE_INDEX),
                header.beacon.stateRoot
            )
        );

        store.finalizedHeader = header;
        store.currentSyncCommittee = currentSyncCommittee;
        store.optimisticHeader = header;

        console.log("ok!");
    }

    function initializeLightClientStore(
        bytes32 trustedBlockRoot,
        LightClientBootstrap memory bootstrap
    ) external {
        require(isValidLightClientHeader(bootstrap.header));

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
