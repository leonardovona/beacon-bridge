pragma solidity ^0.8.17;

import {
    NEXT_SYNC_COMMITTEE_INDEX_LOG_2, FINALIZED_ROOT_INDEX_LOG_2, SYNC_COMMITTEE_SIZE
} from "./Constants.sol";

/*
* The data structures are adapted from the Ethereum specs (except Groth16Proof).
*/

library Structs {
    struct LightClientStore {
        bytes32 currentSyncCommitteeRoot;
        bytes32 nextSyncCommitteeRoot;
        uint64 beaconSlot;
        bytes32 genesisValidatorsRoot;
    }

    struct LightClientUpdate {
        LightClientHeader attestedHeader;
        SyncCommittee nextSyncCommittee;
        bytes32[] nextSyncCommitteeBranch; // Length is NEXT_SYNC_COMMITTEE_INDEX_LOG_2
        LightClientHeader finalizedHeader;
        bytes32[] finalityBranch; // Length is FINALIZED_ROOT_INDEX_LOG_2
        SyncAggregate syncAggregate;
        uint64 signatureSlot;
    }

    struct SyncAggregate {
        bool[SYNC_COMMITTEE_SIZE] syncCommitteeBits;
        bytes syncCommitteeSignature; // bytes96
    }

    struct BeaconBlockHeader {
        bytes32 parentRoot;
        bytes32 stateRoot;
        bytes32 bodyRoot;
        uint64 slot;
        uint64 proposerIndex;
    }

    struct ExecutionPayloadHeader {
        bytes32 parentHash;
        bytes32 stateRoot;
        bytes32 receiptsRoot;
        bytes32 prevRandao;
        uint64 blockNumber;
        uint64 gasLimit;
        uint64 gasUsed;
        uint64 timestamp;
        uint256 baseFeePerGas;
        bytes32 blockHash;
        bytes32 transactionsRoot;
        bytes32 withdrawalsRoot;
        bytes20 feeRecipient;
        bytes logsBloom; // Length is BYTES_PER_LOGS_BLOOM
        bytes extraData;
    }

    struct LightClientHeader {
        BeaconBlockHeader beacon;
        ExecutionPayloadHeader execution;
        bytes32[] executionBranch; // Lenght is EXECUTION_PAYLOAD_INDEX_LOG_2
    }

    struct SyncCommittee {
        bytes[SYNC_COMMITTEE_SIZE] pubkeys; // bytes48
        bytes aggregatePubkey; // bytes48
    }

    struct LightClientBootstrap {
        LightClientHeader header;
        SyncCommittee currentSyncCommittee;
        bytes32[] currentSyncCommitteeBranch; // Lenght is CURRENT_SYNC_COMMITTEE_INDEX_LOG_2
    }

    // Represents a Groth16 proof
    struct Groth16Proof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
    }
}
