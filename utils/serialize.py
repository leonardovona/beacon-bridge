"""
Utility functions for serializing data structures to strings and JSON
"""

from utils.specs import LightClientBootstrap, LightClientUpdate, LightClientHeader, SyncCommittee, SyncAggregate, Domain
from utils.ssz.ssz_impl import hash_tree_root

def light_client_header_to_string(header: LightClientHeader):
    """
    Convert a light client header to a string
    """
    res = "["
    # Beacon block header
    res += "["
    res += "\"" + str(header.beacon.parent_root) + "\","
    res += "\"" + str(header.beacon.state_root) + "\","
    res += "\"" + str(header.beacon.body_root) + "\","
    res += str(header.beacon.slot) + ","
    res += str(header.beacon.proposer_index)
    res += "],"
    # Execution payload header
    res += "["
    res += "\"" + str(header.execution.parent_hash) + "\","
    res += "\"" + str(header.execution.state_root) + "\","
    res += "\"" + str(header.execution.receipts_root) + "\","
    res += "\"" + str(header.execution.prev_randao) + "\","
    res += str(header.execution.block_number) + ","
    res += str(header.execution.gas_limit) + ","
    res += str(header.execution.gas_used) + ","
    res += str(header.execution.timestamp) + ","
    res += str(header.execution.base_fee_per_gas) + ","
    res += "\"" + str(header.execution.block_hash) + "\","
    res += "\"" + str(header.execution.transactions_root) + "\","
    res += "\"" + str(header.execution.withdrawals_root) + "\","
    res += "\"" + str(header.execution.fee_recipient) + "\","
    res += "\"" + str(header.execution.logs_bloom) + "\","
    res += "\"" + str(header.execution.extra_data) + "\""
    res += "],"
    # Execution branch
    res += "["
    for i in range(len(header.execution_branch) - 1):
        res += "\"" + str(header.execution_branch[i]) + "\","
    res += "\"" + str(header.execution_branch[len(header.execution_branch) - 1]) + "\""
    res += "]"
    res += "]"
    return res


def sync_committee_to_string(committee: SyncCommittee):
    """
    Convert a sync committee to a string
    """
    res = "["
    # Pubkeys
    res += "["
    for i in range(len(committee.pubkeys) - 1):
        res += "\"" + str(committee.pubkeys[i]) + "\","
    res += "\"" + str(committee.pubkeys[len(committee.pubkeys) - 1]) + "\""
    res += "],"
    res += "\"" + str(committee.aggregate_pubkey) + "\""
    res += "]"
    return res


def branch_to_string(branch):
    """
    Convert a sync committee / finality branch to a string
    """
    res = "["
    for i in range(len(branch) - 1):
        res += "\"" + str(branch[i]) + "\","
    res += "\"" + str(branch[len(branch) - 1]) + "\""
    res += "]"
    return res


def sync_aggregate_to_string(aggregate: SyncAggregate):
    """
    Convert a sync aggregate to a string
    """
    res = "["
    res += "["
    for i in range(len(aggregate.sync_committee_bits) - 1):
        if(aggregate.sync_committee_bits[i]):
            res += "True,"
        else:
            res += "False,"
    if(aggregate.sync_committee_bits[len(aggregate.sync_committee_bits) - 1]):
        res += "True"
    else:
        res += "False"
    res += "],"
    res += "\"" + str(aggregate.sync_committee_signature) + "\""
    res += "]"
    return res


def light_client_bootstrap_to_string(bootstrap: LightClientBootstrap):
    """
    Convert a light client bootstrap to a string
    """
    res = "["
    # Header
    res += light_client_header_to_string(bootstrap.header) + ","
    # Current sync committee
    res += sync_committee_to_string(bootstrap.current_sync_committee) + ","
    # current sync committee branch
    res += branch_to_string(bootstrap.current_sync_committee_branch)
    res += "]"
    return res    


def light_client_update_to_string(update: LightClientUpdate):
    """
    Convert a light client update to a string
    """
    res = "["
    # Attested Header
    res += light_client_header_to_string(update.attested_header) + ","
    # Next sync committee
    res += sync_committee_to_string(update.next_sync_committee) + ","
    # next sync committee branch
    res += branch_to_string(update.next_sync_committee_branch) + ","
    # finalized header
    res += light_client_header_to_string(update.finalized_header) + ","
    # finality branch
    res += branch_to_string(update.finality_branch) + ","
    # sync aggregate
    res += sync_aggregate_to_string(update.sync_aggregate) + ","
    # signature slot
    res += str(update.signature_slot)
    res += "]"
    return res

def convert_rotate_data_to_JSON(syncCommittee: SyncCommittee):
    json = "{\n"
    json += "\t\"pubkeys\": [\n"
    for i in range(len(syncCommittee.pubkeys)):
        json += "\t\t\"" + str(syncCommittee.pubkeys[i]) + "\""
        if i != len(syncCommittee.pubkeys) - 1:
            json += ",\n"
        else:
            json += "\n"
    json += "\t],\n"
    json += "\t\"syncCommitteeSSZ\": \"" + str(hash_tree_root(syncCommittee)) + "\"\n"
    json += "}"
    return json

def step_data_to_JSON(
        sync_committee: SyncCommittee,
        sync_committee_bits,
        sync_committee_signature,
        signing_root,
        participation,
        sync_committee_poseidon):
    json = "{\n"
    json += "\t\"pubkeys\": [\n"
    for i in range(len(sync_committee.pubkeys)):
        json += "\t\t\"" + str(sync_committee.pubkeys[i]) + "\""
        if i != len(sync_committee.pubkeys) - 1:
            json += ",\n"
        else:
            json += "\n"
    json += "\t],\n"
    json += "\t\"pubkeybits\": [\n"
    for i in range(len(sync_committee_bits)):
        json += "\t\t" + str(int(sync_committee_bits[i]))
        if i != len(sync_committee_bits) - 1:
            json += ", "
    json += "\t],\n"
    json += "\t\"signature\": \"" + str(sync_committee_signature) + "\",\n"
    json += "\t\"signingRoot\": \"" + str(signing_root) + "\",\n"
    json += "\t\"participation\": " + str(participation) + ",\n"
    json += "\t\"syncCommitteePoseidon\": \"" + str(sync_committee_poseidon) + "\"\n"
    json += "}"
    return json
