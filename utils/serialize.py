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

def convert_sync_committee_poseidon_data_to_JSON(pubkeys):
    json = "{\n"
    json += "\t\"pubkeys\": [\n"
    for i in range(len(pubkeys)):
        json += "\t\t\"" + str(pubkeys[i]) + "\""
        if i != len(pubkeys) - 1:
            json += ",\n"
        else:
            json += "\n"
    json += "\t]\n"
    json += "}"
    return json


def my_rotate_data_to_JSON(
        sync_committee: SyncCommittee,
        sync_committee_poseidon: str,
        sync_committee_branch,
        finalized_header: LightClientHeader):
    """
    Convert a sync committee to a JSON string
    """
    json = "{\n"
    json += "\t\"pubkeys\": [\n"
    for i in range(len(sync_committee.pubkeys)):
        json += "\t\t\"" + str(sync_committee.pubkeys[i]) + "\""
        if i != len(sync_committee.pubkeys) - 1:
            json += ",\n"
        else:
            json += "\n"
    json += "\t],\n"
    json += "\t\"syncCommitteeBranch\": [\n"
    for i in range(len(sync_committee_branch)):
        json += "\t\t\"" + str(sync_committee_branch[i]) + "\""
        if i != len(sync_committee_branch) - 1:
            json += ",\n"
        else:
            json += "\n"
    json += "\t],\n"
    json += "\t\"syncCommitteePoseidon\": \"" + str(sync_committee_poseidon) + "\",\n"
    json += "\t\"finalizedHeaderRoot\": \"" + str(hash_tree_root(finalized_header.beacon)) + "\",\n"
    json += "\t\"finalizedSlot\": " + str(finalized_header.beacon.slot) + ",\n"
    json += "\t\"finalizedProposerIndex\": " + str(finalized_header.beacon.proposer_index) + ",\n"
    json += "\t\"finalizedParentRoot\": \"" + str(finalized_header.beacon.parent_root) + "\",\n"
    json += "\t\"finalizedStateRoot\": \"" + str(finalized_header.beacon.state_root) + "\",\n"
    json += "\t\"finalizedBodyRoot\": \"" + str(finalized_header.beacon.body_root) + "\",\n"
    json += "}"
    return json

def validate_light_client_update_data_to_JSON(
        attested_header: LightClientHeader,
        finalized_header: LightClientHeader,
        sync_committee: SyncCommittee, 
        syncCommitteeBits, 
        signature: bytes, 
        domain: Domain,
        signing_root: bytes,
        participation: int,
        sync_committee_poseidon,
        finality_branch,
        execution_state_root,
        execution_branch,
        public_inputs_poseidon
    ):
    """
    Convert signature verification data to a JSON string
    """
    json = "{\n"
    json += "\t\"attestedHeaderRoot\": \"" + str(hash_tree_root(attested_header.beacon)) + "\",\n"
    json += "\t\"attestedSlot\": " + str(attested_header.beacon.slot) + ",\n"
    json += "\t\"attestedProposerIndex\": " + str(attested_header.beacon.proposer_index) + ",\n"
    json += "\t\"attestedParentRoot\": \"" + str(attested_header.beacon.parent_root) + "\",\n"
    json += "\t\"attestedStateRoot\": \"" + str(attested_header.beacon.state_root) + "\",\n"
    json += "\t\"attestedBodyRoot\": \"" + str(attested_header.beacon.body_root) + "\",\n"
    json += "\t\"finalizedHeaderRoot\": \"" + str(hash_tree_root(finalized_header.beacon)) + "\",\n"
    json += "\t\"finalizedSlot\": " + str(finalized_header.beacon.slot) + ",\n"
    json += "\t\"finalizedProposerIndex\": " + str(finalized_header.beacon.proposer_index) + ",\n"
    json += "\t\"finalizedParentRoot\": \"" + str(finalized_header.beacon.parent_root) + "\",\n"
    json += "\t\"finalizedStateRoot\": \"" + str(finalized_header.beacon.state_root) + "\",\n"
    json += "\t\"finalizedBodyRoot\": \"" + str(finalized_header.beacon.body_root) + "\",\n"
    json += "\t\"pubkeys\": [\n"
    for i in range(len(sync_committee.pubkeys)):
        json += "\t\t\"" + str(sync_committee.pubkeys[i]) + "\""
        if i != len(sync_committee.pubkeys) - 1:
            json += ",\n"
        else:
            json += "\n"
    json += "\t],\n"
    json += "\t\"aggregationBits\": [\n"
    for i in range(len(syncCommitteeBits)):
        json += "\t\t" + str(int(syncCommitteeBits[i]))
        if i != len(syncCommitteeBits) - 1:
            json += ", "
    json += "\t],\n"
    json += "\t\"signature\": \"" + str(signature) + "\",\n"
    json += "\t\"domain\": \"" + str(domain) + "\",\n"
    json += "\t\"signingRoot\": \"" + str(signing_root) + "\"\n"
    json += "\t\"participation\": " + str(participation) + ",\n"
    json += "\t\"syncCommitteePoseidon\": \"" + str(sync_committee_poseidon) + "\",\n"
    json += "\t\"finalityBranch\": [\n"
    for i in range(len(finality_branch)):
        json += "\t\t\"" + str(finality_branch[i]) + "\""
        if i != len(finality_branch) - 1:
            json += ",\n"
        else:
            json += "\n"
    json += "\t],\n"
    json += "\t\"executionStateRoot\": \"" + str(execution_state_root) + "\",\n"
    json += "\t\"executionStateBranch\": [\n"
    for i in range(len(execution_branch)):
        json += "\t\t\"" + str(execution_branch[i]) + "\""
        if i != len(execution_branch) - 1:
            json += ",\n"
        else:
            json += "\n"
    json += "\t],\n"
    json += "\t\"publicInputsRoot\": \"" + str(public_inputs_poseidon) + "\"\n"
    json += "}"
    return json

def sync_committee_ssz_data_to_JSON(sync_committee: SyncCommittee):
    json = "{\n"
    json += "\t\"pubkeys\": [\n"
    for i in range(len(sync_committee.pubkeys)):
        json += "\t\t\"" + str(sync_committee.pubkeys[i]) + "\""
        if i != len(sync_committee.pubkeys) - 1:
            json += ",\n"
        else:
            json += "\n"
    json += "\t],\n"
    json += "\t\"aggregatePubkey\": \"" + str(sync_committee.aggregate_pubkey) + "\",\n"
    json += "\t\"syncCommitteeSSZ\": \"" + str(hash_tree_root(sync_committee)) + "\"\n"
    json += "}"
    return json

def my_step_data_to_JSON(
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
