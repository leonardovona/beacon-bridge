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

from utils.ssz.ssz_typing import Bytes32
from utils.clock import get_current_slot, time_until_next_epoch
# specs is the package that contains the executable specifications of the Ethereum Beacon chain
from utils.specs import (
    Root, compute_sync_committee_period_at_slot, MAX_REQUEST_LIGHT_CLIENT_UPDATES,
    LightClientOptimisticUpdate, LightClientUpdate, Slot,
    LightClientFinalityUpdate, EPOCHS_PER_SYNC_COMMITTEE_PERIOD, compute_epoch_at_slot,
    SyncCommittee, LightClientHeader)
from utils.beacon_middleware import (
    get_trusted_block_root, get_light_client_bootstrap, get_finality_update, get_updates_for_period, get_genesis_validators_root
)
from utils.contract_middleware import (
    init_contract, initialize_light_client_store, process_light_client_update
)
import math, asyncio


# Takes into account possible clock drifts. The low value provides protection against a server sending updates too far in the future
MAX_CLOCK_DISPARITY_SEC = 10
FINALITY_UPDATE_POLL_INTERVAL = 48  # Da modificare
LOOKAHEAD_EPOCHS_COMMITTEE_SYNC = 8
NEXT_SYNC_COMMITTEE_INDEX_LOG_2 = 5
FINALIZED_ROOT_INDEX_LOG_2 = 6


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


async def handle_finality_updates():
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
                process_light_client_finality_update(finality_update,
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
        updates = get_updates_for_period(from_period, count)

        for update in updates:
            print("Processing update")
            process_light_client_update(update, get_current_slot(tolerance=MAX_CLOCK_DISPARITY_SEC), genesis_validators_root)
            

async def main():
    """
    Main function of the light client
    """
    global genesis_validators_root
    genesis_validators_root = get_genesis_validators_root()
        
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
    print("Start finality update handler")
    asyncio.create_task(handle_finality_updates())

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
    init_contract()
    asyncio.run(main())