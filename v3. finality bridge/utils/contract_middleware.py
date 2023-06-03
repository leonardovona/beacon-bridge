from web3 import Web3, HTTPProvider
from solcx import install_solc, compile_source

from utils.specs import (
    Root, LightClientBootstrap, LightClientStore, MyLightClientStore, SyncCommittee, LightClientUpdate, Slot,
    compute_sync_committee_period_at_slot
)

from utils.to_string import light_client_bootstrap_to_string, light_client_update_to_string, sync_committee_to_string

from utils.ssz.ssz_typing import uint64

import asyncio, ast

def init_web3():
    global web3

    web3 = Web3(HTTPProvider('http://localhost:7545', request_kwargs={'timeout': 300}))
    web3.eth.default_account = web3.eth.accounts[0]


def compile_contract():
    install_solc('0.8.17')
    with open ('./contracts/lightClient.sol', 'r') as file:
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
    global light_client 

    init_web3()
    LightClient, abi = compile_contract()
    tx_hash = LightClient.constructor().transact({'gas': 30_000_000})
    tx_receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
    light_client = web3.eth.contract(address=tx_receipt.contractAddress, abi=abi)


def initialize_light_client_store(trusted_block_root: Root, 
                                  bootstrap: LightClientBootstrap) -> LightClientStore:
    global store
    store = MyLightClientStore(
        beacon_slot=uint64(0),
        current_sync_committee=SyncCommittee(),
        next_sync_committee=SyncCommittee(),
        previous_max_active_participants=uint64(0),
        current_max_active_participants=uint64(0)
    )

    light_client_bootstrap = ast.literal_eval(light_client_bootstrap_to_string(bootstrap))
    trusted_block_root = str(trusted_block_root)

    event_filter = light_client.events.BootstrapComplete.create_filter(fromBlock='latest')

    light_client.functions.initializeLightClientStore(
        light_client_bootstrap,
        trusted_block_root
    ).transact()

    while True:
        entries = event_filter.get_new_entries()
        if len(entries) > 0:
            break
        asyncio.sleep(2)
    store.beacon_slot = bootstrap.header.beacon.slot
    store.current_sync_committee = bootstrap.current_sync_committee
    
    
def process_light_client_update(update: LightClientUpdate,
                                current_slot: Slot,
                                genesis_validators_root: Root) -> None:
    
    store_period = compute_sync_committee_period_at_slot(store.beacon_slot)
    update_signature_period = compute_sync_committee_period_at_slot(update.signature_slot)

    sync_committee = SyncCommittee()
    if(update_signature_period == store_period):
        sync_committee = store.current_sync_committee
    else:
        sync_committee = store.next_sync_committee

    light_client_update = ast.literal_eval(light_client_update_to_string(update))
    current_slot = int(str(current_slot))
    genesis_validators_root = str(genesis_validators_root)
    sync_committee = ast.literal_eval(sync_committee_to_string(sync_committee))
    
    event_filter = light_client.events.UpdateProcessed.create_filter(fromBlock='latest')

    tx_hash = light_client.functions.processLightClientUpdate(
        light_client_update,
        current_slot,
        genesis_validators_root,
        sync_committee
    ).transact({'gas': 30_000_000})

    while True:
        entries = event_filter.get_new_entries()
        if len(entries) > 0:
            break
        asyncio.sleep(2)

    update_finalized_period = compute_sync_committee_period_at_slot(update.finalized_header.beacon.slot)

    if store.next_sync_committee != SyncCommittee():
       store.next_sync_committee = update.next_sync_committee
    elif update_finalized_period == store_period + 1:
        store.current_sync_committee = store.next_sync_committee
        store.next_sync_committee = update.next_sync_committee
        store.previous_max_active_participants = store.current_max_active_participants
        store.current_max_active_participants = 0
    if update.finalized_header.beacon.slot > store.beacon_slot:
        store.beacon_slot = update.finalized_header.beacon.slot