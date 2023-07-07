pragma solidity ^0.8.17;

import "./Structs.sol";
import "./Utils.sol";

/*
* @dev Library for Merkle tree hashing and verification.
*/
contract Merkleize {
    // zeroHashes[i] contains the hash tree root of a Merkle tree with 2**i zero leaves.
    bytes32[10] zeroHashes;
    
    // Initializes zeroHashes.
    function initZeroHashes() private {
        for (uint256 layer = 1; layer < 10; ++layer) {
            zeroHashes[layer] = sha256(abi.encodePacked(zeroHashes[layer - 1], zeroHashes[layer - 1]));
        }
    }

    constructor(){ initZeroHashes(); }

    /*
    * @author https://github.com/ethereum/consensus-specs/blob/v1.3.0/tests/core/pyspec/eth2spec/utils/merkle_minimal.py#L7
    * @dev Utility function for merkleize_chunks. Merges an element of the Merkle tree with the partial result.
    * @param h The element to be merged.
    * @param i The index of the element in the chunks list.
    * @param count The total number of elements in the chunks list.
    * @param depth The depth of the Merkle tree.
    * @param tmp The partial result.
    * @return The partial Merkle root.
    */
    function merge(
        bytes32 h,
        uint256 i,
        uint256 count,
        uint256 depth,
        bytes32[] memory tmp
    ) private view {
        uint256 j;
        while (true) {
            if (i & (1 << j) == 0) {
                if (i == count && j < depth) {
                    h = sha256(abi.encodePacked(h, zeroHashes[j]));
                } else {
                    break;
                }
            } else {
                h = sha256(abi.encodePacked(tmp[j], h));
            }
            ++j;
        }

        tmp[j] = h;
    }

    /*
    * @author https://github.com/ethereum/consensus-specs/blob/v1.3.0/tests/core/pyspec/eth2spec/utils/merkle_minimal.py#L7
    * @dev Computes the Merkle root of a list of chunks.
    * @param chunks The list of chunks.
    * @param limit The maximum number of chunks to be processed.
    * @return The Merkle root.
    */
    function merkleize_chunks(bytes32[] memory chunks, uint256 limit) public view returns (bytes32) {
        uint256 count = chunks.length;

        if (limit == 0) {
            return zeroHashes[0];
        }

        // Depth of the Merkle tree.
        uint256 depth = Utils.log2({x: count - 1, ceil: true});
        if (depth == 0) depth = 1;

        // Maximum depth according to limit.
        uint256 max_depth = Utils.log2({x: limit - 1, ceil: true});
        
        // Where to store partial results.
        bytes32[] memory tmp = new bytes32[](max_depth + 1);

        // Compute the Merkle root.
        for (uint256 i; i < count; ++i) {
            merge(chunks[i], i, count, depth, tmp);
        }

        // If the number of chunks is not a power of two, merge with an empty chunk.
        if (1 << depth != count) {
            merge(zeroHashes[0], count, count, depth, tmp);
        }

        // Pad the partial results with zero hashes to reach max_depth.
        for (uint256 j = depth; j < max_depth; ++j) {
            tmp[j + 1] = sha256(abi.encodePacked(tmp[j], zeroHashes[j]));
        }

        return tmp[max_depth];
    }

    /*
    The logic for the computation of the hash tree root is described in:
        https://eth2book.info/capella/part2/building_blocks/merkleization/
    */

    /*
    * @dev Computes the hash tree root of a beacon block header.
    * @param header The beacon block header.
    * @return The hash tree root.
    */
    function hashTreeRoot(Structs.BeaconBlockHeader memory header) public view returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](5);
        chunks[0] = Utils.toBytes(header.slot);
        chunks[1] = Utils.toBytes(header.proposerIndex);
        chunks[2] = header.parentRoot;
        chunks[3] = header.stateRoot;
        chunks[4] = header.bodyRoot;

        return merkleize_chunks(chunks, 5);
    }

    /*
    * @dev Computes the hash tree root of a set of sync committee pubkeys.
    * @param pubkeys The set of sync committee pubkeys.
    * @return The hash tree root.
    */
    function hashTreeRoot(bytes[SYNC_COMMITTEE_SIZE] memory pubkeys) public view returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](SYNC_COMMITTEE_SIZE);
        for (uint256 i; i < SYNC_COMMITTEE_SIZE; ++i) {
            chunks[i] = sha256(abi.encodePacked(pubkeys[i], bytes16(0)));
        }

        return merkleize_chunks(chunks, SYNC_COMMITTEE_SIZE);
    }

    /*
    * @dev Computes the hash tree root of a sync committee.
    * @param syncCommittee The sync committee.
    * @return The hash tree root.
    */
    function hashTreeRoot(Structs.SyncCommittee memory syncCommittee) public view returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](2);
        chunks[0] = hashTreeRoot(syncCommittee.pubkeys);
        chunks[1] = sha256(
            abi.encodePacked(syncCommittee.aggregatePubkey, bytes16(0))
        );

        return merkleize_chunks(chunks, 2);
    }

    /*
    * @dev Computes the hash tree root of an execution payload header.
    * @param header The execution payload header.
    * @return The hash tree root.
    */
    function hashTreeRoot(Structs.ExecutionPayloadHeader memory header) public view returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](15);

        chunks[0] = header.parentHash;
        chunks[1] = bytes32(abi.encodePacked(header.feeRecipient, bytes12(0)));
        chunks[2] = header.stateRoot;
        chunks[3] = header.receiptsRoot;

        bytes32[] memory chunksLogsBloom = new bytes32[](256 / 32);
        for (uint256 i; i < (256 / 32); ++i) {
            bytes memory temp = new bytes(32);
            for (uint256 j; j < 32; ++j) {
                temp[j] = header.logsBloom[i * 32 + j];
            }
            chunksLogsBloom[i] = bytes32(temp);
        }
        chunks[4] = merkleize_chunks(chunksLogsBloom, 256 / 32);

        chunks[5] = header.prevRandao;
        chunks[6] = Utils.toBytes(header.blockNumber);
        chunks[7] = Utils.toBytes(header.gasLimit);
        chunks[8] = Utils.toBytes(header.gasUsed);
        chunks[9] = Utils.toBytes(header.timestamp);

        bytes32[] memory chunksExtraData = new bytes32[](2);
        chunksExtraData[0] = bytes32(
            abi.encodePacked(header.extraData, new bytes(32 - header.extraData.length)));
        chunksExtraData[1] = bytes32(Utils.reverse(header.extraData.length));
        chunks[10] = merkleize_chunks(chunksExtraData, 2);

        chunks[11] = bytes32(Utils.reverse(header.baseFeePerGas));
        chunks[12] = header.blockHash;
        chunks[13] = header.transactionsRoot;
        chunks[14] = header.withdrawalsRoot;

        return merkleize_chunks(chunks, 15);
    }

    /*
    * @dev Check if leaf at index verifies against the Merkle root and branch.
    * @param leaf The leaf to be verified.
    * @param branch The Merkle branch.
    * @param depth The depth of the Merkle tree.
    * @param index The index of the leaf.
    * @param root The Merkle root.
    * @return True if the leaf verifies against the Merkle root and branch.
    */
    function isValidMerkleBranch(
        bytes32 leaf,
        bytes32[] calldata branch,
        uint64 depth,
        uint256 index,
        bytes32 root
    ) public pure returns (bool) {
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
}