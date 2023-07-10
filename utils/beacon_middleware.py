"""
Middleware for beacon chain data
"""
import requests
from utils.specs import Root, LightClientBootstrap, LightClientFinalityUpdate
from utils.parsing import parse_header, parse_sync_committee, parse_sync_aggregate, parse_light_client_updates

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


def get_updates_for_period(sync_period, count):
    """
    Retrieve the sync committee updates for a given sync period
    """
    sync_period = str(sync_period)
    updates = beacon_api(f"{ENDPOINT_NODE_URL}/eth/v1/beacon/light_client/updates?start_period={sync_period}&count={count}")
    return parse_light_client_updates(updates)


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
        header=parse_header(response['header']),
        current_sync_committee=parse_sync_committee(
            response['current_sync_committee']),
        current_sync_committee_branch=response['current_sync_committee_branch']
    )


def get_finality_update():
    """
    Retrieve and parse the latest finality update from the beacon chain node
    """
    finality_update = beacon_api(
        f"{ENDPOINT_NODE_URL}/eth/v1/beacon/light_client/finality_update")['data']

    return LightClientFinalityUpdate(
        attested_header=parse_header(
            finality_update['attested_header']),
        finalized_header=parse_header(
            finality_update['finalized_header']),
        finality_branch=finality_update['finality_branch'],
        sync_aggregate=parse_sync_aggregate(
            finality_update['sync_aggregate']),
        signature_slot=int(finality_update['signature_slot'])
    )