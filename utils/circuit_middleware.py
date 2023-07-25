"""
Middleware for zk circuits
"""

import subprocess
import json

from utils.serialize import my_rotate_data_to_JSON, validate_light_client_update_data_to_JSON, convert_sync_committee_poseidon_data_to_JSON, my_step_data_to_JSON
from utils.specs import SyncCommittee, LightClientHeader

def poseidon_committment(
        sync_committee: SyncCommittee,
        sync_committee_branch,
        finalized_header: LightClientHeader
    ): 
    """
    Generate poseidon hash and proof for sync committee committment
    """
    
    # convert sync committee to a format suitable for zk circuis
    with open('./data/sync_committee_poseidon_data.json', 'w') as file:
        file.write(convert_sync_committee_poseidon_data_to_JSON(sync_committee.pubkeys))
    subprocess.run(["ts-node", "./ts/convert_sync_committee_poseidon.ts"])
    subprocess.run(["./circuits/scripts/sync_committee_poseidon.sh"], shell=True)
    with open('./build/convert_sync_committee_poseidon_public.json', 'r') as file:
        sync_committee_poseidon = hex(int(json.load(file)[1]))

    # generate sync committee poseidon hash and proof
    with open('./data/my_rotate_data.json', 'w') as file:
        file.write(my_rotate_data_to_JSON(
            sync_committee,
            sync_committee_poseidon,
            sync_committee_branch,
            finalized_header))
    subprocess.run(["ts-node", "./ts/convert_sync_committee.ts"])
    subprocess.run(["./circuits/scripts/build_sync_committee_committments.sh"], shell=True)

    # retrieve sync committee poseidon proof
    with open('./build/my_rotate_proof.json', 'r') as file:
        proof = json.load(file)
        proof = [
            [int(proof['pi_a'][0]), int(proof['pi_a'][1])], 
            [
                [int(proof['pi_b'][0][1]), int(proof['pi_b'][0][0])], 
                [int(proof['pi_b'][1][1]), int(proof['pi_b'][1][0])]
            ], 
            [int(proof['pi_c'][0]), int(proof['pi_c'][1])]
        ]

    return sync_committee_poseidon, proof


def validate_light_client_update(
        sync_committee, 
        sync_committee_bits,
        sync_committee_signature, 
        signing_root,
        participation,
        sync_committee_poseidon
    ):

    """
    Generate signature proof for a signed header
    """
    with open('./data/my_step_data.json', 'w') as file:
        file.write(my_step_data_to_JSON(
            sync_committee,
            sync_committee_bits,
            sync_committee_signature,
            signing_root,
            participation,
            sync_committee_poseidon
            ))
    subprocess.run(["ts-node", "./ts/convert_my_step_data.ts"])
    exit()

    # generate signature proof
    subprocess.run(["./circuits/scripts/my_step.sh"], shell=True)
    
    # retrieve bls verify proof
    with open('./build/my_step_proof.json', 'r') as file:
        signature_proof = json.load(file)
        signature_proof = [
            [int(signature_proof['pi_a'][0]), int(signature_proof['pi_a'][1])], 
            [
                [int(signature_proof['pi_b'][0][1]), int(signature_proof['pi_b'][0][0])], 
                [int(signature_proof['pi_b'][1][1]), int(signature_proof['pi_b'][1][0])]
            ], 
            [int(signature_proof['pi_c'][0]), int(signature_proof['pi_c'][1])]
        ]
    
    return signature_proof