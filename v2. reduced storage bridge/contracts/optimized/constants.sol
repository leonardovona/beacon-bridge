pragma solidity ^0.8.17;

// Constants
uint8 constant CURRENT_SYNC_COMMITTEE_INDEX = 54;
uint8 constant CURRENT_SYNC_COMMITTEE_INDEX_LOG_2 = 5;
uint256 constant EXECUTION_PAYLOAD_INDEX = 25;
uint8 constant EXECUTION_PAYLOAD_INDEX_LOG_2 = 4;
uint16 constant SYNC_COMMITTEE_SIZE = 512;
uint16 constant BYTES_PER_LOGS_BLOOM = 256;
uint8 constant SLOTS_PER_EPOCH = 32;
uint32 constant CAPELLA_FORK_EPOCH = 194048;
uint32 constant ALTAIR_FORK_EPOCH = 74240;
uint32 constant BELLATRIX_FORK_EPOCH = 144896;
uint64 constant NEXT_SYNC_COMMITTEE_INDEX_LOG_2 = 5;
uint64 constant FINALIZED_ROOT_INDEX_LOG_2 = 6;
uint8 constant MIN_SYNC_COMMITTEE_PARTICIPANTS = 1;
uint64 constant EPOCHS_PER_SYNC_COMMITTEE_PERIOD = 256;
uint64 constant FINALIZED_ROOT_INDEX = 105;
uint8 constant GENESIS_SLOT = 0;
uint64 constant NEXT_SYNC_COMMITTEE_INDEX = 55;
bytes4 constant ALTAIR_FORK_VERSION = bytes4(uint32(1));
bytes4 constant BELLATRIX_FORK_VERSION = bytes4(uint32(2));
bytes4 constant CAPELLA_FORK_VERSION = bytes4(uint32(3));
bytes4 constant GENESIS_FORK_VERSION = bytes4(uint32(0));
bytes4 constant DOMAIN_SYNC_COMMITTEE = bytes4(uint32(7));