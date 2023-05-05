from utils.specs import (
    Root, initialize_light_client_store, LightClientBootstrap, BeaconBlockHeader, 
    LightClientHeader, BeaconBlockHeader, Slot, ValidatorIndex, ExecutionPayloadHeader,
    Hash32, ExecutionAddress, floorlog2, EXECUTION_PAYLOAD_INDEX, BLSPubkey, SYNC_COMMITTEE_SIZE,
    SyncCommittee, CURRENT_SYNC_COMMITTEE_INDEX, LightClientUpdate, SyncAggregate)

from utils.ssz.ssz_typing import (
    Bytes32, uint64, Container, Vector, Bytes48, ByteVector, ByteList,
    uint256, Bytes20, Bitvector, Bytes96, Bytes4, View)


def hex_to_bytes(hex_string):
    if hex_string[:2] == '0x':
        hex_string = hex_string[2:] 
    byte_string = bytes.fromhex(hex_string)
    return byte_string 

def hex_to_bits(hex_string):
    int_representation = int(hex_string, 16)
    binary_vector = bin(int_representation) 
    if binary_vector[:2] == '0b':
        binary_vector = binary_vector[2:]
    return binary_vector 


def parse_beacon_block_header(beacon):
    return BeaconBlockHeader(
        slot = int(beacon['slot']),
        proposer_index = int(beacon['proposer_index']),
        parent_root = beacon['parent_root'],
        state_root = beacon['state_root'],
        body_root = beacon['body_root']
    )


def parse_execution_payload_header(execution):
    return ExecutionPayloadHeader(
        parent_hash = execution['parent_hash'],
        fee_recipient = execution['fee_recipient'],
        state_root = execution['state_root'],
        receipts_root = execution['receipts_root'],
        logs_bloom = execution['logs_bloom'],
        prev_randao = execution['prev_randao'],
        block_number = int(execution['block_number']),
        gas_limit = int(execution['gas_limit']),
        gas_used = int(execution['gas_used']),
        timestamp = int(execution['timestamp']),
        extra_data = execution['extra_data'],
        base_fee_per_gas = int(execution['base_fee_per_gas']),
        block_hash = execution['block_hash'],
        transactions_root = execution['transactions_root'],
        withdrawals_root = execution['withdrawals_root']
    )


# def parse_execution_branch(execution_branch):
#     for i in range(len(execution_branch)):
#         execution_branch[i] = hex_to_bytes(execution_branch[i])
    
#     return execution_branch


def parse_header(header):
    return LightClientHeader(
        beacon = parse_beacon_block_header(header['beacon']),
        execution = parse_execution_payload_header(header['execution']),
        #execution_branch = parse_execution_branch(header['execution_branch']),
        execution_branch = header['execution_branch'],
    )


def parse_sync_committee(current_sync_committee):
    # for i in range(len(current_sync_committee['pubkeys'])):
    #    current_sync_committee['pubkeys'][i] = current_sync_committee['pubkeys'][i]
    
    return SyncCommittee(
        pubkeys = current_sync_committee['pubkeys'],
        aggregate_pubkey = current_sync_committee['aggregate_pubkey']
    )


# def parse_current_sync_committee_branch(current_sync_committee_branch):
#     for i in range(len(current_sync_committee_branch)):
#         current_sync_committee_branch[i] = current_sync_committee_branch[i]
    
#     return current_sync_committee_branch

def parse_sync_aggregate(aggregate_message):
    return SyncAggregate(
        sync_committee_bits = hex_to_bits(aggregate_message['sync_committee_bits']), 
        sync_committee_signature = aggregate_message['sync_committee_signature']
    )

def parse_light_client_update(update):
    return LightClientUpdate(
        attested_header = parse_header(update['attested_header']),
        next_sync_committee = parse_sync_committee(update['next_sync_committee']),
        next_sync_committee_branch = update['next_sync_committee_branch'],
        finalized_header = parse_header(update['finalized_header']),
        finality_branch = update['finality_branch'],
        sync_aggregate = parse_sync_aggregate(update['sync_aggregate']),
        signature_slot = int(update['signature_slot'])
    )

def parse_light_client_updates(updates):
    parsed_updates = []
    for update in updates:
        parsed_updates.append(parse_light_client_update(update['data']))
    return parsed_updates