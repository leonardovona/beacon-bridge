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

from py_ecc.bls import G2ProofOfPossession as py_ecc_bls

# specs is the package that contains the executable specifications of the Ethereum Beacon chain
from utils.specs import (
    Root, LightClientBootstrap, initialize_light_client_store, compute_sync_committee_period_at_slot, process_light_client_update, MAX_REQUEST_LIGHT_CLIENT_UPDATES,
    LightClientOptimisticUpdate, process_light_client_optimistic_update, process_light_client_finality_update,
    LightClientFinalityUpdate, EPOCHS_PER_SYNC_COMMITTEE_PERIOD, compute_epoch_at_slot, BLSPubkey, BLSSignature)

# parsing is the package that contains the functions to parse the data returned by the chain node
import utils.parsing as parsing

import requests
import math
import asyncio

# test
from utils.ssz.ssz_impl import hash_tree_root

# clock is the package that contains the functions to manage the chain time
from utils.clock import get_current_slot, time_until_next_epoch

from utils.serialize import light_client_bootstrap_to_string, light_client_update_to_string

# Takes into account possible clock drifts. The low value provides protection against a server sending updates too far in the future
MAX_CLOCK_DISPARITY_SEC = 10

OPTIMISTIC_UPDATE_POLL_INTERVAL = 12
FINALITY_UPDATE_POLL_INTERVAL = 48  # Da modificare

LOOKAHEAD_EPOCHS_COMMITTEE_SYNC = 8

# Fixed beacon chain node endpoint
ENDPOINT_NODE_URL = "https://lodestar-mainnet.chainsafe.io"


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
    # return Root(parsing.hex_to_bytes(beacon_api(f"{ENDPOINT_NODE_URL}/eth/v1/beacon/genesis")['data']['genesis_validators_root']))


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
    # return Root(parsing.hex_to_bytes(beacon_api(f"{ENDPOINT_NODE_URL}/eth/v1/beacon/headers/finalized")['data']['root']))


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
        # current_sync_committee_branch = map(parsing.hex_to_bytes, response['current_sync_committee_branch'])
    )

from utils.ssz.ssz_typing import Vector


def bootstrap():
    """
    Starting point of the synchronization process, it retrieves the light client bootstrap data and initializes the light client store
    """
    trusted_block_root = get_trusted_block_root()
    light_client_bootstrap = get_light_client_bootstrap(trusted_block_root)

    with open("./test/trusted_block_root.txt", "w") as f:
        f.write(str(trusted_block_root))
    
    with open("./test/light_client_bootstrap.txt", "w") as f:
        f.write(light_client_bootstrap_to_string(light_client_bootstrap))

    light_client_store = initialize_light_client_store(
        trusted_block_root, light_client_bootstrap)
    
    return light_client_store


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
        attested_header=parsing.parse_header(
            optimistic_update['attested_header']),
        sync_aggregate=parsing.parse_sync_aggregate(
            optimistic_update['sync_aggregate']),
        signature_slot=int(optimistic_update['signature_slot'])
    )


# !!! eth1/v1/events allows to subscribe to events
async def handle_optimistic_updates(light_client_store):
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
                process_light_client_optimistic_update(light_client_store,
                                                       optimistic_update,
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
        # finality_branch=parsing.hex_to_bytes(finality_update['finality_branch']),
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


def sync(light_client_store, last_period, current_period):
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

        i = 0
        with open("./test/genesis_validators_root", "w") as f:
            f.write(str(genesis_validators_root))
        for update in updates:
            with open("./test/light_client_update_" + str(i) + ".txt", "w") as f:
                f.write(light_client_update_to_string(update))
            with open("./test/current_slot_" + str(i) + ".txt", "w") as f:
                f.write(str(get_current_slot(tolerance=MAX_CLOCK_DISPARITY_SEC)))
            i += 1
            print("Processing update")
            process_light_client_update(light_client_store, update, get_current_slot(
                tolerance=MAX_CLOCK_DISPARITY_SEC), genesis_validators_root)
    

async def main():
    """
    Main function of the light client
    """
    print("Processing bootstrap")
    light_client_store = bootstrap()
    print("Processing bootstrap done")

    print("Start syncing")
    # Compute the current sync period
    current_period = compute_sync_committee_period_at_slot(
        get_current_slot())  # ! cambia con funzioni di mainnet

    # Compute the sync period associated with the optimistic header
    last_period = compute_sync_committee_period_at_slot(
        light_client_store.optimistic_header.beacon.slot)

    # SYNC
    sync(light_client_store, last_period, current_period)
    print("Sync done")

    # subscribe
    print("Start optimistic update handler")
    asyncio.create_task(handle_optimistic_updates(light_client_store))
    print("Start finality update handler")
    asyncio.create_task(handle_finality_updates(light_client_store))

    while True:
        # ! evaluate to insert an optimistic update

        # when close to the end of a sync period poll for sync committee updates
        current_slot = get_current_slot()
        epoch_in_sync_period = compute_epoch_at_slot(
            current_slot) % EPOCHS_PER_SYNC_COMMITTEE_PERIOD

        if (EPOCHS_PER_SYNC_COMMITTEE_PERIOD - epoch_in_sync_period <= LOOKAHEAD_EPOCHS_COMMITTEE_SYNC):
            period = compute_sync_committee_period_at_slot(current_slot)
            sync(period, period)

        print("Polling next sync committee update in",
              time_until_next_epoch(), "secs")
        await asyncio.sleep(time_until_next_epoch())

from utils.specs import BeaconBlockHeader, ExecutionPayloadHeader, ExecutionAddress, BYTES_PER_LOGS_BLOOM, Hash32, MAX_EXTRA_DATA_BYTES

from utils.ssz.ssz_typing import ByteVector, Bytes32, uint64, ByteList, uint256

import hashlib

if __name__ == "__main__":
    asyncio.run(main())

    # zeroHashes = []
    # zeroHashes.append(Hash32(b'\x00'*32))
    # for i in range(1, 100):
    #     zeroHashes.append(Hash32(hashlib.sha256(zeroHashes[i - 1] + zeroHashes[i - 1]).hexdigest()))

    # for i in range(100):
    #     print(zeroHashes[i])
    """
    The following code is used to test bls signature verification, ignore it
    """
    # assert py_ecc_bls.FastAggregateVerify([
    # 		bytes.fromhex("a73eb991aa22cdb794da6fcde55a427f0a4df5a4a70de23a988b5e5fc8c4d844f66d990273267a54dd21579b7ba6a086"),
    # 		bytes.fromhex("b29043a7273d0a2dbc2b747dcf6a5eccbd7ccb44b2d72e985537b117929bc3fd3a99001481327788ad040b4077c47c0d"),
    # 		bytes.fromhex("b928f3beb93519eecf0145da903b40a4c97dca00b21f12ac0df3be9116ef2ef27b2ae6bcd4c5bc2d54ef5a70627efcb7"),
    # 		bytes.fromhex("9446407bcd8e5efe9f2ac0efbfa9e07d136e68b03c5ebc5bde43db3b94773de8605c30419eb2596513707e4e7448bb50"),
    # 	],
    # 	bytes.fromhex("69241e7146cdcc5a5ddc9a60bab8f378c0271e548065a38bcc60624e1dbed97f"),
    # 	bytes.fromhex("b204e9656cbeb79a9a8e397920fd8e60c5f5d9443f58d42186f773c6ade2bd263e2fe6dbdc47f148f871ed9a00b8ac8b17a40d65c8d02120c00dca77495888366b4ccc10f1c6daa02db6a7516555ca0665bca92a647b5f3a514fa083fdc53b6e")
    # 	)

    # my_hex = "d5722733abc981a2e933beb7b1d306ba201e6b3309e44f859a30ab45d85f6669"
    # my_bytes = bytes.fromhex(my_hex)
    # print(my_bytes)

    # print(bytes.fromhex("a73eb991aa22cdb794da6fcde55a427f0a4df5a4a70de23a988b5e5fc8c4d844f66d990273267a54dd21579b7ba6a086"))
    # assert py_ecc_bls.FastAggregateVerify([
    # 		BLSPubkey("0xa73eb991aa22cdb794da6fcde55a427f0a4df5a4a70de23a988b5e5fc8c4d844f66d990273267a54dd21579b7ba6a086"),
    # 		BLSPubkey("0xb29043a7273d0a2dbc2b747dcf6a5eccbd7ccb44b2d72e985537b117929bc3fd3a99001481327788ad040b4077c47c0d"),
    # 		BLSPubkey("0xb928f3beb93519eecf0145da903b40a4c97dca00b21f12ac0df3be9116ef2ef27b2ae6bcd4c5bc2d54ef5a70627efcb7"),
    # 		BLSPubkey("0x9446407bcd8e5efe9f2ac0efbfa9e07d136e68b03c5ebc5bde43db3b94773de8605c30419eb2596513707e4e7448bb50"),
    # 	],
    # 	bytes.fromhex("0x69241e7146cdcc5a5ddc9a60bab8f378c0271e548065a38bcc60624e1dbed97f"),
    # 	BLSSignature("0xb204e9656cbeb79a9a8e397920fd8e60c5f5d9443f58d42186f773c6ade2bd263e2fe6dbdc47f148f871ed9a00b8ac8b17a40d65c8d02120c00dca77495888366b4ccc10f1c6daa02db6a7516555ca0665bca92a647b5f3a514fa083fdc53b6e")
    # 	)
