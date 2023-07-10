"""
Miidleware for interacting with the light client contract
"""
from web3 import Web3, HTTPProvider
from solcx import install_solc, compile_source

from utils.specs import (
    Root, LightClientBootstrap, LightClientStore, MyLightClientStore, SyncCommittee, LightClientUpdate, Slot,
    compute_sync_committee_period_at_slot, compute_fork_version, compute_epoch_at_slot,
    compute_domain, DOMAIN_SYNC_COMMITTEE, compute_signing_root
)

from utils.serialize import light_client_bootstrap_to_string, light_client_update_to_string, sync_committee_to_string

from utils.circuit_middleware import poseidon_committment_verify, validate_signed_header

from utils.ssz.ssz_typing import uint64

import asyncio, ast


def init_web3():
    """
    Initialize web3 instance
    """
    global web3
    web3 = Web3(HTTPProvider('http://localhost:7545', request_kwargs={'timeout': 300}))
    web3.eth.default_account = web3.eth.accounts[0]


def compile_contract():
    """
    Compile the light client contract
    """
    install_solc('0.8.17')
    with open ('./contracts/LightClient.sol', 'r') as file:
        source = file.read()
    compiled_solc = compile_source(source, 
        output_values=['abi', 'bin'], 
        base_path='./contracts', 
        optimize=True, 
        optimize_runs=200,
        solc_version='0.8.17')
    abi = compiled_solc['<stdin>:LightClient']['abi']
    bytecode = compiled_solc['<stdin>:LightClient']['bin']
    LightClient = web3.eth.contract(abi=abi, bytecode=bytecode)
    return LightClient, abi


def init_contract():
    """
    Deploy the light client contract
    """
    global light_client 
    init_web3()
    LightClient, abi = compile_contract()
    tx_hash = LightClient.constructor().transact({'gas': 30_000_000})
    tx_receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
    light_client = web3.eth.contract(address=tx_receipt.contractAddress, abi=abi)


def initialize_light_client_store(trusted_block_root: Root, 
                                  bootstrap: LightClientBootstrap) -> LightClientStore:
    """
    Initialize the light client store with the light client bootstrap data by calling the light client contract
    """
    global store
    store = MyLightClientStore(
        beacon_slot=uint64(0),
        current_sync_committee=SyncCommittee(),
        next_sync_committee=SyncCommittee(),
        previous_max_active_participants=uint64(0),
        current_max_active_participants=uint64(0)
    )

    # generate sync committee poseidon hash and proof
    sync_committee_poseidon, proof = poseidon_committment_verify(bootstrap.current_sync_committee)

    event_filter = light_client.events.BootstrapComplete.create_filter(fromBlock='latest')

    # call initialize light client store
    light_client.functions.initializeLightClientStore(
        ast.literal_eval(light_client_bootstrap_to_string(bootstrap)),
        str(trusted_block_root),
        sync_committee_poseidon,
        proof
    ).transact()

    # wait for BootstrapComplete event
    while True:
        entries = event_filter.get_new_entries()
        if len(entries) > 0:
            break
        asyncio.sleep(2)

    # update local view of light client store
    store.beacon_slot = bootstrap.header.beacon.slot
    store.current_sync_committee = bootstrap.current_sync_committee
    
    
def process_light_client_update(update: LightClientUpdate,
                                current_slot: Slot,
                                genesis_validators_root: Root) -> None:
    """
    Process a light client update by calling the light client contract
    """
    store_period = compute_sync_committee_period_at_slot(store.beacon_slot)
    update_signature_period = compute_sync_committee_period_at_slot(update.signature_slot)

    # get sync committee that signed the update
    sync_committee = SyncCommittee()
    if(update_signature_period == store_period):
        sync_committee = store.current_sync_committee
    else:
        sync_committee = store.next_sync_committee    

    # compute the signing root for header signature verification
    signing_root = compute_signing_root(
        update.attested_header.beacon, 
        compute_domain(
            DOMAIN_SYNC_COMMITTEE, 
            compute_fork_version(compute_epoch_at_slot(max(update.signature_slot, Slot(1)) - Slot(1))), 
            str(genesis_validators_root)
        )
    )

    # verify header signature and generate proof
    signature_proof = validate_signed_header(
        sync_committee, 
        update.sync_aggregate.sync_committee_bits, 
        update.sync_aggregate.sync_committee_signature, 
        signing_root)

    update_finalized_period = compute_sync_committee_period_at_slot(update.finalized_header.beacon.slot)

    if store.next_sync_committee != SyncCommittee() or update_finalized_period == store_period + 1:
        # the update contains a sync committee update
        # generate sync committee poseidon hash and proof
        sync_committee_poseidon, commitment_mapping_proof = poseidon_committment_verify(update.next_sync_committee)
        # call with sync committee update
        light_client.functions.processLightClientUpdate(
            ast.literal_eval(light_client_update_to_string(update)),
            int(str(current_slot)),
            str(genesis_validators_root),
            ast.literal_eval(sync_committee_to_string(sync_committee)),
            sync_committee_poseidon,
            commitment_mapping_proof,
            signature_proof
        ).transact({'gas': 30_000_000})
    else:
        # the update does not contain a sync committee update
        # call without sync committee update
        light_client.functions.processLightClientUpdate(
            ast.literal_eval(light_client_update_to_string(update)),
            int(str(current_slot)),
            str(genesis_validators_root),
            ast.literal_eval(sync_committee_to_string(sync_committee)),
            signature_proof
        ).transact({'gas': 30_000_000})
    
    event_filter = light_client.events.UpdateProcessed.create_filter(fromBlock='latest')

    # wait for UpdateProcessed event
    while True:
        entries = event_filter.get_new_entries()
        if len(entries) > 0:
            break
        asyncio.sleep(2)   

    # update local view of light client store
    if store.next_sync_committee != SyncCommittee():
       store.next_sync_committee = update.next_sync_committee
    elif update_finalized_period == store_period + 1:
        store.current_sync_committee = store.next_sync_committee
        store.next_sync_committee = update.next_sync_committee
        store.previous_max_active_participants = store.current_max_active_participants
        store.current_max_active_participants = 0
    if update.finalized_header.beacon.slot > store.beacon_slot:
        store.beacon_slot = update.finalized_header.beacon.slot