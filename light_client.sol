pragma solidity ^0.8.17;

contract LightClient {
    uint8 constant CURRENT_SYNC_COMMITTEE_INDEX = 54;
    uint8 constant CURRENT_SYNC_COMMITTEE_INDEX_LOG_2 = 5;
    uint8 constant EXECUTION_PAYLOAD_INDEX = 25;
    uint8 constant EXECUTION_PAYLOAD_INDEX_LOG_2 = 4;
    uint16 constant SYNC_COMMITTEE_SIZE = 512;
    uint16 constant BYTES_PER_LOGS_BLOOM = 256;
    uint8 constant SLOTS_PER_EPOCH = 32;
    uint32 constant CAPELLA_FORK_EPOCH = 194048;
    uint constant NEXT_SYNC_COMMITTEE_INDEX_LOG_2 = 5;
    uint constant FINALIZED_ROOT_INDEX_LOG_2 = 6;

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
        bytes syncCommitteeSignature; // should be bytes96
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
        bytes[SYNC_COMMITTEE_SIZE] pubkeys; // should be bytes48
        bytes aggregatePubkey; // should be bytes48
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
        bytes32[] memory branch, //not sure about memory
        uint64 depth,
        uint64 index,
        bytes32 root
    ) private pure returns (bool) {
        bytes32 value = leaf;
        for (uint64 i = 0; i < depth; i++) {
            if (((index / (2 ** i)) % 2) != 0) {
                value = keccak256(abi.encodePacked(branch[i], value)); // or sha256?
            } else {
                value = keccak256(abi.encodePacked(value, branch[i])); // or sha256?
            }
        }
        return value == root;
    }

    function log2(uint64 x) private pure returns (uint64 y) {
        assembly {
            let arg := x
            x := sub(x, 1)
            x := or(x, div(x, 0x02))
            x := or(x, div(x, 0x04))
            x := or(x, div(x, 0x10))
            x := or(x, div(x, 0x100))
            x := or(x, div(x, 0x10000))
            x := or(x, div(x, 0x100000000))
            x := or(x, div(x, 0x10000000000000000))
            x := or(x, div(x, 0x100000000000000000000000000000000))
            x := add(x, 1)
            let m := mload(0x40)
            mstore(
                m,
                0xf8f9cbfae6cc78fbefe7cdc3a1793dfcf4f0e8bbd8cec470b6a28a7a5a3e1efd
            )
            mstore(
                add(m, 0x20),
                0xf5ecf1b3e9debc68e1d9cfabc5997135bfb7a7a3938b7b606b5b4b3f2f1f0ffe
            )
            mstore(
                add(m, 0x40),
                0xf6e4ed9ff2d6b458eadcdf97bd91692de2d4da8fd2d0ac50c6ae9a8272523616
            )
            mstore(
                add(m, 0x60),
                0xc8c0b887b0a8a4489c948c7f847c6125746c645c544c444038302820181008ff
            )
            mstore(
                add(m, 0x80),
                0xf7cae577eec2a03cf3bad76fb589591debb2dd67e0aa9834bea6925f6a4a2e0e
            )
            mstore(
                add(m, 0xa0),
                0xe39ed557db96902cd38ed14fad815115c786af479b7e83247363534337271707
            )
            mstore(
                add(m, 0xc0),
                0xc976c13bb96e881cb166a933a55e490d9d56952b8d4e801485467d2362422606
            )
            mstore(
                add(m, 0xe0),
                0x753a6d1b65325d0c552a4d1345224105391a310b29122104190a110309020100
            )
            mstore(0x40, add(m, 0x100))
            let
                magic
            := 0x818283848586878898a8b8c8d8e8f929395969799a9b9d9e9faaeb6bedeeff
            let
                shift
            := 0x100000000000000000000000000000000000000000000000000000000000000
            let a := div(mul(x, magic), shift)
            y := div(mload(add(m, sub(255, a))), shift)
            y := add(
                y,
                mul(
                    256,
                    gt(
                        arg,
                        0x8000000000000000000000000000000000000000000000000000000000000000
                    )
                )
            )
        }
    }

    function getSubtreeIndex(
        uint64 generalizedIndex
    ) private pure returns (uint64) {
        uint64 two = 2;
        return (generalizedIndex % (two ** (log2(generalizedIndex))));
    }

    function isEmptyExecutionPayloadHeader(
        ExecutionPayloadHeader memory header // not sure about memory
    ) private pure returns (bool) {
        for (uint16 i = 0; i < BYTES_PER_LOGS_BLOOM; i++) {
            if (header.logsBloom[i] != "") return false;
        }

        for (uint i = 0; i < header.extraData.length; i++) {
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

    function isEmptyExecutionBranch(
        bytes32[] memory executionBranch // not sure about memory
    ) private pure returns (bool) {
        for (uint8 i = 0; i < EXECUTION_PAYLOAD_INDEX_LOG_2; i++) {
            if (executionBranch[i] != 0) return false;
        }
        return true;
    }

    function isValidLightCLientHeader(
        LightClientHeader memory header
    ) private pure returns (bool) {
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

    function hashTreeRoot(
        BeaconBlockHeader memory header // not sure about memory
    ) private view returns (bytes32) {
        // ...
    }

    function hashTreeRoot(
        SyncCommittee memory syncCommittee // not sure about memory
    ) private view returns (bytes32) {
        // ...
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
