"""
Middleware for zk circuits
"""

import subprocess
import json

from utils.serialize import convert_rotate_data_to_JSON, step_data_to_JSON
from utils.specs import SyncCommittee

def poseidon_committment(
        sync_committee: SyncCommittee
    ): 
    """
    Generate poseidon hash and proof for sync committee committment
    """
    
    # convert sync committee to a format suitable for zk circuis
    with open('./data/sync_committee_poseidon_data.json', 'w') as file:
        file.write(convert_rotate_data_to_JSON(sync_committee))
    subprocess.run(["ts-node", "./ts/convert_rotate_data.ts"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["./circuits/scripts/rotate.sh"], shell=True)
    with open('./build/rotate/rotate_public.json', 'r') as file:
        sync_committee_poseidon = hex(int(json.load(file)[1]))

    # retrieve sync committee poseidon proof
    with open('./build/rotate/rotate_proof.json', 'r') as file:
        proof = json.load(file)
        proof = [
            [int(proof['pi_a'][0]), int(proof['pi_a'][1])], 
            [
                [int(proof['pi_b'][0][1]), int(proof['pi_b'][0][0])], 
                [int(proof['pi_b'][1][1]), int(proof['pi_b'][1][0])]
            ], 
            [int(proof['pi_c'][0]), int(proof['pi_c'][1])]
        ]

    return proof, sync_committee_poseidon


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
        file.write(step_data_to_JSON(
            sync_committee,
            sync_committee_bits,
            sync_committee_signature,
            signing_root,
            participation,
            sync_committee_poseidon
            ))
    subprocess.run(["ts-node", "./ts/convert_step_data.ts"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # generate signature proof
    subprocess.run(["./circuits/scripts/step.sh"], shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # retrieve bls verify proof
    with open('./build/step/step_proof.json', 'r') as file:
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