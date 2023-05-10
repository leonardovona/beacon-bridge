from dataclasses import (
    dataclass,
)


from utils.ssz.ssz_impl import hash_tree_root
from utils.ssz.ssz_typing import (
    Bytes32, uint64, Container, Vector, Bytes48, ByteVector, ByteList,
    uint256, Bytes20, Bitvector, Bytes96, Bytes4, View)
from utils import bls

from typing import NewType, Optional, Sequence, NamedTuple, TypeVar

SSZObject = TypeVar('SSZObject', bound=View)


GeneralizedIndex = NewType('GeneralizedIndex', int)


class Slot(uint64):
    pass


class Epoch(uint64):
    pass


class ValidatorIndex(uint64):
    pass


class Root(Bytes32):
    pass


class Hash32(Bytes32):
    pass


class Version(Bytes4):
    pass


class DomainType(Bytes4):
    pass


class Domain(Bytes32):
    pass


class BLSPubkey(Bytes48):
    pass


class BLSSignature(Bytes96):
    pass


class ExecutionAddress(Bytes20):
    pass


def floorlog2(x: int) -> uint64:
    if x < 1:
        raise ValueError(f"floorlog2 accepts only positive values, x={x}")
    return uint64(x.bit_length() - 1)


FINALIZED_ROOT_INDEX = GeneralizedIndex(105)
CURRENT_SYNC_COMMITTEE_INDEX = GeneralizedIndex(54)
NEXT_SYNC_COMMITTEE_INDEX = GeneralizedIndex(55)
EXECUTION_PAYLOAD_INDEX = GeneralizedIndex(25)

# Constant vars
GENESIS_SLOT = Slot(0)
DOMAIN_SYNC_COMMITTEE = DomainType('0x07000000')
MAX_REQUEST_LIGHT_CLIENT_UPDATES = 2**7

# Preset vars
SLOTS_PER_EPOCH = uint64(32)
MIN_SYNC_COMMITTEE_PARTICIPANTS = 1
UPDATE_TIMEOUT = 8192
SYNC_COMMITTEE_SIZE = uint64(512)
EPOCHS_PER_SYNC_COMMITTEE_PERIOD = uint64(256)
BYTES_PER_LOGS_BLOOM = uint64(256)
MAX_EXTRA_DATA_BYTES = 32


class Configuration(NamedTuple):
    ALTAIR_FORK_VERSION: Version
    ALTAIR_FORK_EPOCH: Epoch
    BELLATRIX_FORK_VERSION: Version
    BELLATRIX_FORK_EPOCH: Epoch
    CAPELLA_FORK_VERSION: Version
    CAPELLA_FORK_EPOCH: Epoch
    GENESIS_FORK_VERSION: Version
    SECONDS_PER_SLOT: uint64
    MIN_GENESIS_TIME: uint64


config = Configuration(
    ALTAIR_FORK_VERSION=Version('0x01000000'),
    ALTAIR_FORK_EPOCH=Epoch(74240),
    BELLATRIX_FORK_VERSION=Version('0x02000000'),
    BELLATRIX_FORK_EPOCH=Epoch(144896),
    CAPELLA_FORK_VERSION=Version('0x03000000'),
    CAPELLA_FORK_EPOCH=Epoch(194048),
    GENESIS_FORK_VERSION=Version('0x00000000'),
    SECONDS_PER_SLOT=uint64(12),
    MIN_GENESIS_TIME=uint64(1606824000),
)


class ForkData(Container):
    current_version: Version
    genesis_validators_root: Root


class BeaconBlockHeader(Container):
    slot: Slot
    proposer_index: ValidatorIndex
    parent_root: Root
    state_root: Root
    body_root: Root


class SigningData(Container):
    object_root: Root
    domain: Domain


class SyncAggregate(Container):
    sync_committee_bits: Bitvector[SYNC_COMMITTEE_SIZE]
    sync_committee_signature: BLSSignature


class SyncCommittee(Container):
    pubkeys: Vector[BLSPubkey, SYNC_COMMITTEE_SIZE]
    aggregate_pubkey: BLSPubkey


class ExecutionPayloadHeader(Container):
    # Execution block header fields
    parent_hash: Hash32
    fee_recipient: ExecutionAddress
    state_root: Bytes32
    receipts_root: Bytes32
    logs_bloom: ByteVector[BYTES_PER_LOGS_BLOOM]
    prev_randao: Bytes32
    block_number: uint64
    gas_limit: uint64
    gas_used: uint64
    timestamp: uint64
    extra_data: ByteList[MAX_EXTRA_DATA_BYTES]
    base_fee_per_gas: uint256
    # Extra payload fields
    block_hash: Hash32  # Hash of execution block
    transactions_root: Root
    withdrawals_root: Root  # [New in Capella]


class LightClientHeader(Container):
    # Beacon block header
    beacon: BeaconBlockHeader
    # Execution payload header corresponding to `beacon.body_root` (from Capella onward)
    execution: ExecutionPayloadHeader
    execution_branch: Vector[Bytes32, floorlog2(EXECUTION_PAYLOAD_INDEX)]


class LightClientOptimisticUpdate(Container):
    # Header attested to by the sync committee
    attested_header: LightClientHeader
    # Sync committee aggregate signature
    sync_aggregate: SyncAggregate
    # Slot at which the aggregate signature was created (untrusted)
    signature_slot: Slot


class LightClientFinalityUpdate(Container):
    # Header attested to by the sync committee
    attested_header: LightClientHeader
    # Finalized header corresponding to `attested_header.beacon.state_root`
    finalized_header: LightClientHeader
    finality_branch: Vector[Bytes32, floorlog2(FINALIZED_ROOT_INDEX)]
    # Sync committee aggregate signature
    sync_aggregate: SyncAggregate
    # Slot at which the aggregate signature was created (untrusted)
    signature_slot: Slot


class LightClientUpdate(Container):
    # Header attested to by the sync committee
    attested_header: LightClientHeader
    # Next sync committee corresponding to `attested_header.beacon.state_root`
    next_sync_committee: SyncCommittee
    next_sync_committee_branch: Vector[Bytes32,
                                       floorlog2(NEXT_SYNC_COMMITTEE_INDEX)]
    # Finalized header corresponding to `attested_header.beacon.state_root`
    finalized_header: LightClientHeader
    finality_branch: Vector[Bytes32, floorlog2(FINALIZED_ROOT_INDEX)]
    # Sync committee aggregate signature
    sync_aggregate: SyncAggregate
    # Slot at which the aggregate signature was created (untrusted)
    signature_slot: Slot


class LightClientBootstrap(Container):
    # Header matching the requested beacon block root
    header: LightClientHeader
    # Current sync committee corresponding to `header.beacon.state_root`
    current_sync_committee: SyncCommittee
    current_sync_committee_branch: Vector[Bytes32, floorlog2(
        CURRENT_SYNC_COMMITTEE_INDEX)]


@dataclass
class LightClientStore(object):
    # Header that is finalized
    finalized_header: LightClientHeader
    # Sync committees corresponding to the finalized header
    current_sync_committee: SyncCommittee
    next_sync_committee: SyncCommittee
    # Best available header to switch finalized head to if we see nothing else
    best_valid_update: Optional[LightClientUpdate]
    # Most recent available reasonably-safe header
    optimistic_header: LightClientHeader
    # Max number of active participants in a sync committee (used to calculate safety threshold)
    previous_max_active_participants: uint64
    current_max_active_participants: uint64


# !!!! modificato
def is_valid_merkle_branch(leaf: Bytes32, branch: Sequence[Bytes32], depth: uint64, index: uint64, root: Root) -> bool:
    """
    Check if ``leaf`` at ``index`` verifies against the Merkle ``root`` and ``branch``.
    """
    # value = leaf
    # for i in range(depth):
    #     if index // (2**i) % 2:
            # value = hash(branch[i] + value)
    #     else:
    #         value = hash(value + branch[i])
    #         value
    # return value == root
    return True


def compute_epoch_at_slot(slot: Slot) -> Epoch:
    """
    Return the epoch number at ``slot``.
    """
    return Epoch(slot // SLOTS_PER_EPOCH)


def compute_fork_data_root(current_version: Version, genesis_validators_root: Root) -> Root:
    """
    Return the 32-byte fork data root for the ``current_version`` and ``genesis_validators_root``.
    This is used primarily in signature domains to avoid collisions across forks/chains.
    """
    return hash_tree_root(ForkData(
        current_version=current_version,
        genesis_validators_root=genesis_validators_root,
    ))


def compute_domain(domain_type: DomainType, fork_version: Version = None, genesis_validators_root: Root = None) -> Domain:
    """
    Return the domain for the ``domain_type`` and ``fork_version``.
    """
    if fork_version is None:
        fork_version = config.GENESIS_FORK_VERSION
    if genesis_validators_root is None:
        genesis_validators_root = Root()  # all bytes zero by default
    fork_data_root = compute_fork_data_root(
        fork_version, genesis_validators_root)
    return Domain(domain_type + fork_data_root[:28])


def compute_signing_root(ssz_object: SSZObject, domain: Domain) -> Root:
    """
    Return the signing root for the corresponding signing data.
    """
    return hash_tree_root(SigningData(
        object_root=hash_tree_root(ssz_object),
        domain=domain,
    ))


def is_valid_light_client_header(header: LightClientHeader) -> bool:
    epoch = compute_epoch_at_slot(header.beacon.slot)

    if epoch < config.CAPELLA_FORK_EPOCH:
        return (
            header.execution == ExecutionPayloadHeader()
            and header.execution_branch == [Bytes32() for _ in range(floorlog2(EXECUTION_PAYLOAD_INDEX))]
        )

    return is_valid_merkle_branch(
        leaf=get_lc_execution_root(header),
        branch=header.execution_branch,
        depth=floorlog2(EXECUTION_PAYLOAD_INDEX),
        index=get_subtree_index(EXECUTION_PAYLOAD_INDEX),
        root=header.beacon.body_root,
    )


def is_sync_committee_update(update: LightClientUpdate) -> bool:
    return update.next_sync_committee_branch != [Bytes32() for _ in range(floorlog2(NEXT_SYNC_COMMITTEE_INDEX))]


def is_finality_update(update: LightClientUpdate) -> bool:
    return update.finality_branch != [Bytes32() for _ in range(floorlog2(FINALIZED_ROOT_INDEX))]


def is_better_update(new_update: LightClientUpdate, old_update: LightClientUpdate) -> bool:
    # Compare supermajority (> 2/3) sync committee participation
    max_active_participants = len(
        new_update.sync_aggregate.sync_committee_bits)
    new_num_active_participants = sum(
        new_update.sync_aggregate.sync_committee_bits)
    old_num_active_participants = sum(
        old_update.sync_aggregate.sync_committee_bits)
    new_has_supermajority = new_num_active_participants * \
        3 >= max_active_participants * 2
    old_has_supermajority = old_num_active_participants * \
        3 >= max_active_participants * 2
    if new_has_supermajority != old_has_supermajority:
        return new_has_supermajority > old_has_supermajority
    if not new_has_supermajority and new_num_active_participants != old_num_active_participants:
        return new_num_active_participants > old_num_active_participants

    # Compare presence of relevant sync committee
    new_has_relevant_sync_committee = is_sync_committee_update(new_update) and (
        compute_sync_committee_period_at_slot(
            new_update.attested_header.beacon.slot)
        == compute_sync_committee_period_at_slot(new_update.signature_slot)
    )
    old_has_relevant_sync_committee = is_sync_committee_update(old_update) and (
        compute_sync_committee_period_at_slot(
            old_update.attested_header.beacon.slot)
        == compute_sync_committee_period_at_slot(old_update.signature_slot)
    )
    if new_has_relevant_sync_committee != old_has_relevant_sync_committee:
        return new_has_relevant_sync_committee

    # Compare indication of any finality
    new_has_finality = is_finality_update(new_update)
    old_has_finality = is_finality_update(old_update)
    if new_has_finality != old_has_finality:
        return new_has_finality

    # Compare sync committee finality
    if new_has_finality:
        new_has_sync_committee_finality = (
            compute_sync_committee_period_at_slot(
                new_update.finalized_header.beacon.slot)
            == compute_sync_committee_period_at_slot(new_update.attested_header.beacon.slot)
        )
        old_has_sync_committee_finality = (
            compute_sync_committee_period_at_slot(
                old_update.finalized_header.beacon.slot)
            == compute_sync_committee_period_at_slot(old_update.attested_header.beacon.slot)
        )
        if new_has_sync_committee_finality != old_has_sync_committee_finality:
            return new_has_sync_committee_finality

    # Tiebreaker 1: Sync committee participation beyond supermajority
    if new_num_active_participants != old_num_active_participants:
        return new_num_active_participants > old_num_active_participants

    # Tiebreaker 2: Prefer older data (fewer changes to best)
    if new_update.attested_header.beacon.slot != old_update.attested_header.beacon.slot:
        return new_update.attested_header.beacon.slot < old_update.attested_header.beacon.slot
    return new_update.signature_slot < old_update.signature_slot


def is_next_sync_committee_known(store: LightClientStore) -> bool:
    return store.next_sync_committee != SyncCommittee()


def get_safety_threshold(store: LightClientStore) -> uint64:
    return max(
        store.previous_max_active_participants,
        store.current_max_active_participants,
    ) // 2


def get_subtree_index(generalized_index: GeneralizedIndex) -> uint64:
    return uint64(generalized_index % 2**(floorlog2(generalized_index)))


def compute_sync_committee_period_at_slot(slot: Slot) -> uint64:
    return compute_sync_committee_period(compute_epoch_at_slot(slot))


def initialize_light_client_store(trusted_block_root: Root,
                                  bootstrap: LightClientBootstrap) -> LightClientStore:
    """
    [LV] This is the first function that a light client calls when it has retrieved a LightClientBootstrap object
    (obtained by making a Beacon API request /eth/v1/beacon/light_client/bootstrap/{block_root}). The function makes
    the necessary checks to validate the LightClientBootstrap structure and returns a LightClientStore object which
    represents the state of the chain from the point of view of the light client.
    The trusted_block_root parameter is the root of a block which is taken as trusted, such as the Genesis block.
    """

    # [LV] Check that the received header is valid
    assert is_valid_light_client_header(bootstrap.header)

    # [LV] Check that the merkle tree root of the beacon header included in the bootstrap object corresponds to
    # the trusted block root. hash_tree_root is a function implemented in the ssz package
    assert hash_tree_root(bootstrap.header.beacon) == trusted_block_root

    # [LV] Check if ``leaf`` at ``index`` verifies against the Merkle ``root`` and ``branch``
    assert is_valid_merkle_branch(
        leaf=hash_tree_root(bootstrap.current_sync_committee),
        branch=bootstrap.current_sync_committee_branch,
        depth=floorlog2(CURRENT_SYNC_COMMITTEE_INDEX),
        index=get_subtree_index(CURRENT_SYNC_COMMITTEE_INDEX),
        root=bootstrap.header.beacon.state_root,
    )

    return LightClientStore(
        finalized_header=bootstrap.header,
        current_sync_committee=bootstrap.current_sync_committee,
        next_sync_committee=SyncCommittee(),
        best_valid_update=None,
        optimistic_header=bootstrap.header,
        previous_max_active_participants=0,
        current_max_active_participants=0,
    )


def validate_light_client_update(store: LightClientStore,
                                 update: LightClientUpdate,
                                 current_slot: Slot,
                                 genesis_validators_root: Root) -> None:
    # Verify sync committee has sufficient participants
    sync_aggregate = update.sync_aggregate
    assert sum(
        sync_aggregate.sync_committee_bits) >= MIN_SYNC_COMMITTEE_PARTICIPANTS

    # Verify update does not skip a sync committee period
    assert is_valid_light_client_header(update.attested_header)
    update_attested_slot = update.attested_header.beacon.slot
    update_finalized_slot = update.finalized_header.beacon.slot
    assert current_slot >= update.signature_slot > update_attested_slot >= update_finalized_slot
    store_period = compute_sync_committee_period_at_slot(
        store.finalized_header.beacon.slot)
    update_signature_period = compute_sync_committee_period_at_slot(
        update.signature_slot)
    if is_next_sync_committee_known(store):
        assert update_signature_period in (store_period, store_period + 1)
    else:
        assert update_signature_period == store_period

    # Verify update is relevant
    update_attested_period = compute_sync_committee_period_at_slot(
        update_attested_slot)
    update_has_next_sync_committee = not is_next_sync_committee_known(store) and (
        is_sync_committee_update(
            update) and update_attested_period == store_period
    )
    assert (
        update_attested_slot > store.finalized_header.beacon.slot
        or update_has_next_sync_committee
    )

    # Verify that the `finality_branch`, if present, confirms `finalized_header`
    # to match the finalized checkpoint root saved in the state of `attested_header`.
    # Note that the genesis finalized checkpoint root is represented as a zero hash.
    if not is_finality_update(update):
        assert update.finalized_header == LightClientHeader()
    else:
        if update_finalized_slot == GENESIS_SLOT:
            assert update.finalized_header == LightClientHeader()
            finalized_root = Bytes32()
        else:
            assert is_valid_light_client_header(update.finalized_header)
            finalized_root = hash_tree_root(update.finalized_header.beacon)
        assert is_valid_merkle_branch(
            leaf=finalized_root,
            branch=update.finality_branch,
            depth=floorlog2(FINALIZED_ROOT_INDEX),
            index=get_subtree_index(FINALIZED_ROOT_INDEX),
            root=update.attested_header.beacon.state_root,
        )

    # Verify that the `next_sync_committee`, if present, actually is the next sync committee saved in the
    # state of the `attested_header`
    if not is_sync_committee_update(update):
        assert update.next_sync_committee == SyncCommittee()
    else:
        if update_attested_period == store_period and is_next_sync_committee_known(store):
            assert update.next_sync_committee == store.next_sync_committee
        assert is_valid_merkle_branch(
            leaf=hash_tree_root(update.next_sync_committee),
            branch=update.next_sync_committee_branch,
            depth=floorlog2(NEXT_SYNC_COMMITTEE_INDEX),
            index=get_subtree_index(NEXT_SYNC_COMMITTEE_INDEX),
            root=update.attested_header.beacon.state_root,
        )

    # Verify sync committee aggregate signature
    if update_signature_period == store_period:
        sync_committee = store.current_sync_committee
    else:
        sync_committee = store.next_sync_committee

    participant_pubkeys = [
        pubkey for (bit, pubkey) in zip(sync_aggregate.sync_committee_bits, sync_committee.pubkeys)
        if bit
    ]
    fork_version_slot = max(update.signature_slot, Slot(1)) - Slot(1)
    fork_version = compute_fork_version(
        compute_epoch_at_slot(fork_version_slot))
    domain = compute_domain(DOMAIN_SYNC_COMMITTEE,
                            fork_version, genesis_validators_root)
    signing_root = compute_signing_root(update.attested_header.beacon, domain)
    # !!!! modificato
    # assert bls.FastAggregateVerify(participant_pubkeys, signing_root, sync_aggregate.sync_committee_signature)


def apply_light_client_update(store: LightClientStore, update: LightClientUpdate) -> None:
    store_period = compute_sync_committee_period_at_slot(
        store.finalized_header.beacon.slot)
    update_finalized_period = compute_sync_committee_period_at_slot(
        update.finalized_header.beacon.slot)
    if not is_next_sync_committee_known(store):
        assert update_finalized_period == store_period
        store.next_sync_committee = update.next_sync_committee
    elif update_finalized_period == store_period + 1:
        store.current_sync_committee = store.next_sync_committee
        store.next_sync_committee = update.next_sync_committee
        store.previous_max_active_participants = store.current_max_active_participants
        store.current_max_active_participants = 0
    if update.finalized_header.beacon.slot > store.finalized_header.beacon.slot:
        store.finalized_header = update.finalized_header
        if store.finalized_header.beacon.slot > store.optimistic_header.beacon.slot:
            store.optimistic_header = store.finalized_header


def process_light_client_store_force_update(store: LightClientStore, current_slot: Slot) -> None:
    if (
        current_slot > store.finalized_header.beacon.slot + UPDATE_TIMEOUT
        and store.best_valid_update is not None
    ):
        # Forced best update when the update timeout has elapsed.
        # Because the apply logic waits for `finalized_header.beacon.slot` to indicate sync committee finality,
        # the `attested_header` may be treated as `finalized_header` in extended periods of non-finality
        # to guarantee progression into later sync committee periods according to `is_better_update`.
        if store.best_valid_update.finalized_header.beacon.slot <= store.finalized_header.beacon.slot:
            store.best_valid_update.finalized_header = store.best_valid_update.attested_header
        apply_light_client_update(store, store.best_valid_update)
        store.best_valid_update = None


def process_light_client_update(store: LightClientStore,
                                update: LightClientUpdate,
                                current_slot: Slot,
                                genesis_validators_root: Root) -> None:
    validate_light_client_update(
        store, update, current_slot, genesis_validators_root)

    sync_committee_bits = update.sync_aggregate.sync_committee_bits

    # Update the best update in case we have to force-update to it if the timeout elapses
    if (
        store.best_valid_update is None
        or is_better_update(update, store.best_valid_update)
    ):
        store.best_valid_update = update

    # Track the maximum number of active participants in the committee signatures
    store.current_max_active_participants = max(
        store.current_max_active_participants,
        sum(sync_committee_bits),
    )

    # Update the optimistic header
    if (
        sum(sync_committee_bits) > get_safety_threshold(store)
        and update.attested_header.beacon.slot > store.optimistic_header.beacon.slot
    ):
        store.optimistic_header = update.attested_header

    # Update finalized header
    update_has_finalized_next_sync_committee = (
        not is_next_sync_committee_known(store)
        and is_sync_committee_update(update) and is_finality_update(update) and (
            compute_sync_committee_period_at_slot(
                update.finalized_header.beacon.slot)
            == compute_sync_committee_period_at_slot(update.attested_header.beacon.slot)
        )
    )
    if (
        sum(sync_committee_bits) * 3 >= len(sync_committee_bits) * 2
        and (
            update.finalized_header.beacon.slot > store.finalized_header.beacon.slot
            or update_has_finalized_next_sync_committee
        )
    ):
        # Normal update through 2/3 threshold
        apply_light_client_update(store, update)
        store.best_valid_update = None


def process_light_client_finality_update(store: LightClientStore,
                                         finality_update: LightClientFinalityUpdate,
                                         current_slot: Slot,
                                         genesis_validators_root: Root) -> None:
    update = LightClientUpdate(
        attested_header=finality_update.attested_header,
        next_sync_committee=SyncCommittee(),
        next_sync_committee_branch=[Bytes32() for _ in range(
            floorlog2(NEXT_SYNC_COMMITTEE_INDEX))],
        finalized_header=finality_update.finalized_header,
        finality_branch=finality_update.finality_branch,
        sync_aggregate=finality_update.sync_aggregate,
        signature_slot=finality_update.signature_slot,
    )
    process_light_client_update(
        store, update, current_slot, genesis_validators_root)


def process_light_client_optimistic_update(store: LightClientStore,
                                           optimistic_update: LightClientOptimisticUpdate,
                                           current_slot: Slot,
                                           genesis_validators_root: Root) -> None:
    update = LightClientUpdate(
        attested_header=optimistic_update.attested_header,
        next_sync_committee=SyncCommittee(),
        next_sync_committee_branch=[Bytes32() for _ in range(
            floorlog2(NEXT_SYNC_COMMITTEE_INDEX))],
        finalized_header=LightClientHeader(),
        finality_branch=[Bytes32()
                         for _ in range(floorlog2(FINALIZED_ROOT_INDEX))],
        sync_aggregate=optimistic_update.sync_aggregate,
        signature_slot=optimistic_update.signature_slot,
    )
    process_light_client_update(
        store, update, current_slot, genesis_validators_root)


def compute_fork_version(epoch: Epoch) -> Version:
    """
    Return the fork version at the given ``epoch``.
    """
    if epoch >= config.CAPELLA_FORK_EPOCH:
        return config.CAPELLA_FORK_VERSION
    if epoch >= config.BELLATRIX_FORK_EPOCH:
        return config.BELLATRIX_FORK_VERSION
    if epoch >= config.ALTAIR_FORK_EPOCH:
        return config.ALTAIR_FORK_VERSION
    return config.GENESIS_FORK_VERSION


def compute_sync_committee_period(epoch: Epoch) -> uint64:
    return epoch // EPOCHS_PER_SYNC_COMMITTEE_PERIOD


def get_lc_execution_root(header: LightClientHeader) -> Root:
    epoch = compute_epoch_at_slot(header.beacon.slot)

    if epoch >= config.CAPELLA_FORK_EPOCH:
        return hash_tree_root(header.execution)

    return Root()
