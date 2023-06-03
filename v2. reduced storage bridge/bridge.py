"""
This file implements a very basilar light client for the Ethereum Beacon chain.
It uses the executable specifications defined in
    https://github.com/ethereum/consensus-specs/
and is based on the description of the light client behavior explained in 
    https://github.com/ethereum/consensus-specs/blob/dev/specs/altair/light-client/light-client.md 

Some parts of the code are adapted from:
    https://github.com/ChainSafe/lodestar/tree/unstable/packages/light-client
    https://github.com/EchoAlice/python-light-client/tree/light-client

The life cycle of the light client is the following:
    1. Bootstrap
        1a. Get a trusted block root (e.g., last finalized block) from a node of the chain
        1b. Get the light client bootstrap data using the trusted block root
        1c. Initialize the light client store with the light client bootstrap data
    2. Sync
        2a. Get the sync committee updates from the trusted block sync period to the current sync period
        2b. Process and update the light client store
    3. Start the following tasks:
        3a. Poll for optimistic updates
        3b. Poll for finality updates
        3c. Poll for sync committee updates
"""

from utils.ssz.ssz_typing import Bytes32, uint64

from utils.to_string import light_client_bootstrap_to_string, light_client_update_to_string, sync_committee_to_string

from web3 import Web3, HTTPProvider
from solcx import install_solc, compile_source
import ast

from utils.clock import get_current_slot, time_until_next_epoch

# specs is the package that contains the executable specifications of the Ethereum Beacon chain
from utils.specs import (
    Root, LightClientBootstrap, compute_sync_committee_period_at_slot, MAX_REQUEST_LIGHT_CLIENT_UPDATES,
    LightClientOptimisticUpdate, LightClientStore, LightClientUpdate, Slot,
    LightClientFinalityUpdate, EPOCHS_PER_SYNC_COMMITTEE_PERIOD, compute_epoch_at_slot,
    SyncCommittee, LightClientHeader)

from dataclasses import dataclass

from web3 import Web3, HTTPProvider

# parsing is the package that contains the functions to parse the data returned by the chain node
import utils.parsing as parsing

import requests
import math
import asyncio

# Takes into account possible clock drifts. The low value provides protection against a server sending updates too far in the future
MAX_CLOCK_DISPARITY_SEC = 10

OPTIMISTIC_UPDATE_POLL_INTERVAL = 12
FINALITY_UPDATE_POLL_INTERVAL = 48  # Da modificare

LOOKAHEAD_EPOCHS_COMMITTEE_SYNC = 8

# Fixed beacon chain node endpoint
ENDPOINT_NODE_URL = "https://lodestar-mainnet.chainsafe.io"

web3 = Web3(HTTPProvider('http://localhost:7545', request_kwargs={'timeout': 300}))
web3.eth.default_account = web3.eth.accounts[0]

light_client = None

@dataclass
class MyLightClientStore(object):
    beacon_slot: uint64
    current_sync_committee: SyncCommittee
    next_sync_committee: SyncCommittee
    previous_max_active_participants: uint64
    current_max_active_participants: uint64

store = MyLightClientStore(
    beacon_slot=uint64(0),
    current_sync_committee=SyncCommittee(),
    next_sync_committee=SyncCommittee(),
    previous_max_active_participants=uint64(0),
    current_max_active_participants=uint64(0)
)

def initialize_light_client_store(trusted_block_root: Root,
                                  bootstrap: LightClientBootstrap) -> LightClientStore:
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
            # print(entries)
            break
        asyncio.sleep(2)
    # tx_receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
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
    ).transact({'gas': 100_000_000})

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


def beacon_api(url):
    """
    Retrieve data by means of the beacon chain node API
    """
    response = requests.get(url)
    assert response.ok
    return response.json()


def get_genesis_validators_root():
    """
    Retrieve the genesis validators root from the beacon chain node
    """
    return Root(beacon_api(f"{ENDPOINT_NODE_URL}/eth/v1/beacon/genesis")['data']['genesis_validators_root'])


genesis_validators_root = get_genesis_validators_root()


def updates_for_period(sync_period, count):
    """
    Retrieve the sync committee updates for a given sync period
    """
    sync_period = str(sync_period)
    return beacon_api(f"{ENDPOINT_NODE_URL}/eth/v1/beacon/light_client/updates?start_period={sync_period}&count={count}")


def get_trusted_block_root():
    """
    Retrieve the last finalized block root from the beacon chain node
    """
    return Root(beacon_api(f"{ENDPOINT_NODE_URL}/eth/v1/beacon/headers/finalized")['data']['root'])


def get_light_client_bootstrap(trusted_block_root):
    """
    Retrieve and parse the light client bootstrap data from the beacon chain node
    """
    response = beacon_api(
        f"{ENDPOINT_NODE_URL}/eth/v1/beacon/light_client/bootstrap/{trusted_block_root}")['data']

    return LightClientBootstrap(
        header=parsing.parse_header(response['header']),
        current_sync_committee=parsing.parse_sync_committee(
            response['current_sync_committee']),
        current_sync_committee_branch=response['current_sync_committee_branch']
    )


def bootstrap():
    """
    Starting point of the synchronization process, it retrieves the light client bootstrap data and initializes the light client store
    """
    trusted_block_root = get_trusted_block_root()
    light_client_bootstrap = get_light_client_bootstrap(trusted_block_root)

    initialize_light_client_store(trusted_block_root, light_client_bootstrap)

    return light_client_bootstrap.header.beacon.slot


def chunkify_range(from_period, to_period, items_per_chunk):
    """
    Split a range of sync committee periods into chunks of a given size.
    Necessary because the beacon chain node API does not allow to retrieve more than a given amount of
    sync committee updates at a time
    """
    if items_per_chunk < 1:
        items_per_chunk = 1

    total_items = to_period - from_period + 1

    chunk_count = max(math.ceil(int(total_items) / items_per_chunk), 1)

    chunks = []
    for i in range(chunk_count):
        _from = from_period + i * items_per_chunk
        _to = min(from_period + (i + 1) * items_per_chunk - 1, to_period)
        chunks.append([_from, _to])
        if _to >= to_period:
            break
    return chunks


def get_optimistic_update():
    """
    Retrieve and parse the latest optimistic update from the beacon chain node
    """
    optimistic_update = beacon_api(
        f"{ENDPOINT_NODE_URL}/eth/v1/beacon/light_client/optimistic_update")['data']

    return LightClientOptimisticUpdate(
        attested_header=parsing.parse_header(optimistic_update['attested_header']),
        sync_aggregate=parsing.parse_sync_aggregate(optimistic_update['sync_aggregate']),
        signature_slot=int(optimistic_update['signature_slot'])
    )

NEXT_SYNC_COMMITTEE_INDEX_LOG_2 = 5
FINALIZED_ROOT_INDEX_LOG_2 = 6

def process_light_client_finality_update(finality_update: LightClientFinalityUpdate,
                                         current_slot: Slot,
                                         genesis_validators_root: Root) -> None:
    update = LightClientUpdate(
        attested_header=finality_update.attested_header,
        next_sync_committee=SyncCommittee(),
        next_sync_committee_branch=[Bytes32() for _ in range(NEXT_SYNC_COMMITTEE_INDEX_LOG_2)],
        finalized_header=finality_update.finalized_header,
        finality_branch=finality_update.finality_branch,
        sync_aggregate=finality_update.sync_aggregate,
        signature_slot=finality_update.signature_slot,
    )

    process_light_client_update(update, current_slot, genesis_validators_root)


def process_light_client_optimistic_update(optimistic_update: LightClientOptimisticUpdate,
                                           current_slot: Slot,
                                           genesis_validators_root: Root) -> None:
    update = LightClientUpdate(
        attested_header=optimistic_update.attested_header,
        next_sync_committee=SyncCommittee(),
        next_sync_committee_branch=[Bytes32() for _ in range(NEXT_SYNC_COMMITTEE_INDEX_LOG_2)],
        finalized_header=LightClientHeader(),
        finality_branch=[Bytes32() for _ in range(FINALIZED_ROOT_INDEX_LOG_2)],
        sync_aggregate=optimistic_update.sync_aggregate,
        signature_slot=optimistic_update.signature_slot,
    )

    process_light_client_update(update, current_slot, genesis_validators_root)

# !!! eth1/v1/events allows to subscribe to events
async def handle_optimistic_updates():
    """
    Tasks which periodically retrieves the latest optimistic update from the beacon chain node and processes it
    """
    last_optimistic_update = None
    while True:
        try:
            optimistic_update = get_optimistic_update()

            if last_optimistic_update is None or last_optimistic_update.attested_header.beacon.slot != optimistic_update.attested_header.beacon.slot:
                last_optimistic_update = optimistic_update
                print("Processing optimistic update: slot",
                      optimistic_update.attested_header.beacon.slot)
                process_light_client_optimistic_update(optimistic_update,
                                                       get_current_slot(
                                                           tolerance=MAX_CLOCK_DISPARITY_SEC),
                                                       genesis_validators_root)
        # In case of sync_committee_bits length is less than 512, remerkleable throws an Exception
        # In case of failure during API call, beacon_api throws an AssertionError
        except (AssertionError, Exception):
            print("Unable to retrieve optimistic update")

        await asyncio.sleep(OPTIMISTIC_UPDATE_POLL_INTERVAL)


def get_finality_update():
    """
    Retrieve and parse the latest finality update from the beacon chain node
    """
    finality_update = beacon_api(
        f"{ENDPOINT_NODE_URL}/eth/v1/beacon/light_client/finality_update")['data']

    return LightClientFinalityUpdate(
        attested_header=parsing.parse_header(
            finality_update['attested_header']),
        finalized_header=parsing.parse_header(
            finality_update['finalized_header']),
        finality_branch=finality_update['finality_branch'],
        sync_aggregate=parsing.parse_sync_aggregate(
            finality_update['sync_aggregate']),
        signature_slot=int(finality_update['signature_slot'])
    )


async def handle_finality_updates(light_client_store):
    """
    Tasks which periodically retrieves the latest finality update from the beacon chain node and processes it
    """
    last_finality_update = None
    while True:
        try:
            finality_update = get_finality_update()
            if last_finality_update is None or last_finality_update.finalized_header.beacon.slot != finality_update.finalized_header.beacon.slot:
                last_finality_update = finality_update
                print("Processing finality update: slot",
                      last_finality_update.finalized_header.beacon.slot)
                process_light_client_finality_update(light_client_store,
                                                     finality_update,
                                                     get_current_slot(
                                                         tolerance=MAX_CLOCK_DISPARITY_SEC),
                                                     genesis_validators_root)
        # In case of sync_committee_bits length is less than 512, remerkleable throws an Exception
        # In case of failure during API call, beacon_api throws an AssertionError
        except (AssertionError, Exception):
            print("Unable to retrieve finality update")

        await asyncio.sleep(FINALITY_UPDATE_POLL_INTERVAL)


def sync(last_period, current_period):
    """
    Sync the light client store with the beacon chain for a given sync committee period range
    """
    # split the period range into chunks of MAX_REQUEST_LIGHT_CLIENT_UPDATES
    period_ranges = chunkify_range(
        last_period, current_period, MAX_REQUEST_LIGHT_CLIENT_UPDATES)

    for (from_period, to_period) in period_ranges:
        count = to_period + 1 - from_period
        updates = updates_for_period(from_period, count)
        updates = parsing.parse_light_client_updates(updates)

        for update in updates:
            print("Processing update")
            process_light_client_update(update, get_current_slot(tolerance=MAX_CLOCK_DISPARITY_SEC), genesis_validators_root)


def compile_contract():
    install_solc('0.8.17')
    with open ('./contracts/optimized/lightClient.sol', 'r') as file:
        source = file.read()
    compiled_solc = compile_source(source, 
        output_values=['abi', 'bin'], 
        base_path='./contracts/optimized', 
        optimize=True, 
        optimize_runs=200,
        solc_version='0.8.17')
    abi = compiled_solc['<stdin>:LightClient']['abi']
    bytecode = compiled_solc['<stdin>:LightClient']['bin']
    LightClient = web3.eth.contract(abi=abi, bytecode=bytecode)
    return LightClient, abi


def init_contract(LightClient, abi):
    tx_hash = LightClient.constructor().transact({'gas': 100_000_000})
    tx_receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
    return web3.eth.contract(address=tx_receipt.contractAddress, abi=abi)


async def main():
    """
    Main function of the light client
    """
    print("Processing bootstrap")
    bootstrap_slot = bootstrap()
    print("Processing bootstrap done")

    print("Start syncing")
    # Compute the current sync period
    current_period = compute_sync_committee_period_at_slot(get_current_slot())  # ! cambia con funzioni di mainnet

    # Compute the sync period associated with the optimistic header
    last_period = compute_sync_committee_period_at_slot(bootstrap_slot)

    # SYNC
    sync(last_period, current_period)
    print("Sync done")
    # subscribe
    print("Start optimistic update handler")
    asyncio.create_task(handle_optimistic_updates())
    # print("Start finality update handler")
    # asyncio.create_task(handle_finality_updates(light_client_store))

    while True:
        # ! evaluate to insert an optimistic update

        # when close to the end of a sync period poll for sync committee updates
        current_slot = get_current_slot()
        epoch_in_sync_period = compute_epoch_at_slot(current_slot) % EPOCHS_PER_SYNC_COMMITTEE_PERIOD

        if (EPOCHS_PER_SYNC_COMMITTEE_PERIOD - epoch_in_sync_period <= LOOKAHEAD_EPOCHS_COMMITTEE_SYNC):
            period = compute_sync_committee_period_at_slot(current_slot)
            sync(period, period)

        print("Polling next sync committee update in", time_until_next_epoch(), "secs")
        await asyncio.sleep(time_until_next_epoch())


if __name__ == "__main__":
    LightClient, abi = compile_contract()
    light_client = init_contract(LightClient, abi)
    asyncio.run(main())