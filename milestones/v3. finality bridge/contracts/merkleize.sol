pragma solidity ^0.8.17;

import "./structs.sol";
import "./utils.sol";

contract Merkleize {

    bytes32[10] zeroHashes; // not sure if 10 is enough

    // Initialization
    function initZeroHashes() private {
        for (uint256 layer = 1; layer < 10; ++layer) {
            zeroHashes[layer] = sha256(abi.encodePacked(zeroHashes[layer - 1], zeroHashes[layer - 1]));
        }
    }

    constructor(){ initZeroHashes(); }

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

    // Adapted from https://github.com/ethereum/consensus-specs/blob/v1.3.0/tests/core/pyspec/eth2spec/utils/merkle_minimal.py#L7
    function merkleize_chunks(bytes32[] memory chunks, uint256 limit) public view returns (bytes32) {
        uint256 count = chunks.length;

        // if(count > limit) raise exception

        if (limit == 0) {
            return zeroHashes[0];
        }

        uint256 depth = Utils.log2({x: count - 1, ceil: true});
        if (depth == 0) depth = 1;

        uint256 max_depth = Utils.log2({x: limit - 1, ceil: true});

        bytes32[] memory tmp = new bytes32[](max_depth + 1);

        for (uint256 i; i < count; ++i) {
            merge(chunks[i], i, count, depth, tmp);
        }

        if (1 << depth != count) {
            merge(zeroHashes[0], count, count, depth, tmp);
        }

        for (uint256 j = depth; j < max_depth; ++j) {
            tmp[j + 1] = sha256(abi.encodePacked(tmp[j], zeroHashes[j]));
        }

        return tmp[max_depth];
    }

    // https://eth2book.info/capella/part2/building_blocks/merkleization/
    function hashTreeRoot(Structs.BeaconBlockHeader memory header) public view returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](5);
        chunks[0] = Utils.toBytes(header.slot);
        chunks[1] = Utils.toBytes(header.proposerIndex);
        chunks[2] = header.parentRoot;
        chunks[3] = header.stateRoot;
        chunks[4] = header.bodyRoot;

        return merkleize_chunks(chunks, 5);
    }

    function hashTreeRoot(bytes[SYNC_COMMITTEE_SIZE] memory pubkeys) public view returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](SYNC_COMMITTEE_SIZE);
        for (uint256 i; i < SYNC_COMMITTEE_SIZE; ++i) {
            chunks[i] = sha256(abi.encodePacked(pubkeys[i], bytes16(0)));
        }

        return merkleize_chunks(chunks, SYNC_COMMITTEE_SIZE);
    }

    function hashTreeRoot(Structs.SyncCommittee memory syncCommittee) public view returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](2);
        chunks[0] = hashTreeRoot(syncCommittee.pubkeys);
        chunks[1] = sha256(
            abi.encodePacked(syncCommittee.aggregatePubkey, bytes16(0))
        );

        return merkleize_chunks(chunks, 2);
    }

    function hashTreeRoot(Structs.ExecutionPayloadHeader memory header) public view returns (bytes32) {
        bytes32[] memory chunks = new bytes32[](15);

        chunks[0] = header.parentHash;
        chunks[1] = bytes32(abi.encodePacked(header.feeRecipient, bytes12(0))); //not sure
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
}