pragma solidity ^0.8.17;

import {
    NEXT_SYNC_COMMITTEE_INDEX_LOG_2, FINALIZED_ROOT_INDEX_LOG_2, SYNC_COMMITTEE_SIZE
} from "./constants.sol";

library Structs {
    //Types definition
    struct LightClientStore {
        bytes32 currentSyncCommitteeRoot;
        bytes32 nextSyncCommitteeRoot;
        uint64 beaconSlot;
        uint64 previousMaxActiveParticipants;
        uint64 currentMaxActiveParticipants;
    }


    struct LightClientUpdate {
        LightClientHeader attestedHeader;
        SyncCommittee nextSyncCommittee;
        bytes32[] nextSyncCommitteeBranch; // NEXT_SYNC_COMMITTEE_INDEX_LOG_2 length
        LightClientHeader finalizedHeader;
        bytes32[] finalityBranch; // FINALIZED_ROOT_INDEX_LOG_2 length
        SyncAggregate syncAggregate;
        uint64 signatureSlot;
    }

    struct SyncAggregate {
        bool[SYNC_COMMITTEE_SIZE] syncCommitteeBits;
        bytes syncCommitteeSignature; // should be bytes96
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
        bytes logsBloom; // BYTES_PER_LOGS_BLOOM len
        bytes extraData;
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
}
