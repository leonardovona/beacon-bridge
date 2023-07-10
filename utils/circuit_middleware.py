"""
Middleware for zk circuits
"""

import subprocess
import json

from utils.serialize import sync_committee_to_JSON, signature_verify_data_to_JSON
from utils.specs import SyncCommittee


def poseidon_committment_verify(sync_committee: SyncCommittee): 
    """
    Generate poseidon hash and proof for sync committee committment
    """

    # convert sync committee to a format suitable for zk circuis
    with open('./data/syncCommittee.json', 'w') as file:
        file.write(sync_committee_to_JSON(sync_committee))
    subprocess.run(["ts-node", "./ts/convert_sync_committee.ts"])

    # generate sync committee poseidon hash and proof
    subprocess.run(["./circuits/scripts/build_sync_committee_committments.sh"], shell=True)

    # retrieve sync committee poseidon hash and proof
    with open('./build/sync_committee_committments_cpp/sync_committee_committments_public.json', 'r') as file:
        sync_committee_poseidon = hex(int(json.load(file)[1]))
    with open('./build/sync_committee_committments_cpp/sync_committee_committments_proof.json', 'r') as file:
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


def validate_signed_header(sync_committee, sync_committee_bits, sync_committee_signature, signing_root):
    """
    Generate signature proof for a signed header
    """

    # convert signature verify input to a format suitable for zk circuis
    with open('./data/signature_verify.json', 'w') as file:
        file.write(signature_verify_data_to_JSON(sync_committee, sync_committee_bits, sync_committee_signature, signing_root))
    subprocess.run(["ts-node", "./ts/convert_valid_signed_header.ts"])
    
    # generate signature proof
    subprocess.run(["./circuits/scripts/build_assert_valid_signed_header.sh"], shell=True)

    # retrieve bls verify proof
    with open('./build/build_assert_valid_signed_header_cpp/build_assert_valid_signed_header_proof.json', 'r') as file:
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