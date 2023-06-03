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
        slot=int(beacon['slot']),
        proposer_index=int(beacon['proposer_index']),
        parent_root=beacon['parent_root'],
        state_root=beacon['state_root'],
        body_root=beacon['body_root']
        # parent_root=hex_to_bytes(beacon['parent_root']),
        # state_root=hex_to_bytes(beacon['state_root']),
        # body_root=hex_to_bytes(beacon['body_root'])
    )


def parse_execution_payload_header(execution):
    return ExecutionPayloadHeader(
        parent_hash=execution['parent_hash'],
        fee_recipient=execution['fee_recipient'],
        state_root=execution['state_root'],
        receipts_root=execution['receipts_root'],
        logs_bloom=execution['logs_bloom'],
        prev_randao=execution['prev_randao'],
        extra_data=execution['extra_data'],
        block_hash=execution['block_hash'],
        transactions_root=execution['transactions_root'],
        withdrawals_root=execution['withdrawals_root'],

        # parent_hash=hex_to_bytes(execution['parent_hash']),
        # fee_recipient=hex_to_bytes(execution['fee_recipient']),
        # state_root=hex_to_bytes(execution['state_root']),
        # receipts_root=hex_to_bytes(execution['receipts_root']),
        # logs_bloom=hex_to_bytes(execution['logs_bloom']),
        # prev_randao=hex_to_bytes(execution['prev_randao']),
        # extra_data=hex_to_bytes(execution['extra_data']),
        # block_hash=hex_to_bytes(execution['block_hash']),
        # transactions_root=hex_to_bytes(execution['transactions_root']),
        # withdrawals_root=hex_to_bytes(execution['withdrawals_root']),

        block_number=int(execution['block_number']),
        gas_limit=int(execution['gas_limit']),
        gas_used=int(execution['gas_used']),
        timestamp=int(execution['timestamp']),
        base_fee_per_gas=int(execution['base_fee_per_gas'])
    )


def parse_header(header):
    return LightClientHeader(
        beacon=parse_beacon_block_header(header['beacon']),
        execution=parse_execution_payload_header(header['execution']),
        # execution_branch=map(hex_to_bytes, header['execution_branch']),
        execution_branch=header['execution_branch'],
    )


def parse_sync_committee(sync_committee):
    return SyncCommittee(
        pubkeys = sync_committee['pubkeys'],
        # pubkeys=map(hex_to_bytes, sync_committee['pubkeys']),
        aggregate_pubkey=sync_committee['aggregate_pubkey']
    )


def parse_sync_aggregate(sync_aggregate):
    return SyncAggregate(
        # Sometimes the sync committee bits are not 512 bits long, in that case it throws an Exception
        sync_committee_bits=hex_to_bits(
            sync_aggregate['sync_committee_bits']),
        sync_committee_signature=sync_aggregate['sync_committee_signature']
        # sync_committee_signature=hex_to_bytes(sync_aggregate['sync_committee_signature'])
    )


def parse_light_client_update(update):
    return LightClientUpdate(
        attested_header=parse_header(update['attested_header']),
        next_sync_committee=parse_sync_committee(
            update['next_sync_committee']),
        next_sync_committee_branch=update['next_sync_committee_branch'],
        finality_branch=update['finality_branch'],
        # next_sync_committee_branch=map(hex_to_bytes, update['next_sync_committee_branch']),
        # finality_branch=map(hex_to_bytes, update['finality_branch']),
        finalized_header=parse_header(update['finalized_header']),
        sync_aggregate=parse_sync_aggregate(update['sync_aggregate']),
        signature_slot=int(update['signature_slot'])
    )


def parse_light_client_updates(updates):
    return [parse_light_client_update(update['data']) for update in updates]
    # parsed_updates = []
    # for update in updates:
    #     parsed_updates.append(parse_light_client_update(update['data']))
    # return parsed_updates
