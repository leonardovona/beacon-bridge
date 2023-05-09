
from utils.specs import (
    Slot, SLOTS_PER_EPOCH, Epoch, EPOCHS_PER_SYNC_COMMITTEE_PERIOD, config
)

from utils.ssz.ssz_typing import uint64

import time
import math


# class SyncPeriod(uint64):
#     pass


# def compute_epoch_at_slot(slot: Slot):
#     """
#     Return the epoch number at the given slot
#     """
#     return Epoch(math.floor(int(slot) / int(SLOTS_PER_EPOCH)))


# def compute_sync_period_at_slot(slot: Slot):
#     """
#     Return the sync committee period at slot
#     """
#     return compute_sync_period_at_epoch(compute_epoch_at_slot(slot))


# def compute_sync_period_at_epoch(epoch: Epoch):
#     """
#     Return the sync committee period at epoch
#     """
#     return SyncPeriod(math.floor(int(epoch) / int(EPOCHS_PER_SYNC_COMMITTEE_PERIOD)))


def get_current_slot(tolerance=0):
    """
    Tolerance is used to account for clock drift
    """
    diff_in_seconds = time.time() - config.MIN_GENESIS_TIME + tolerance
    return Slot(math.floor(diff_in_seconds / config.SECONDS_PER_SLOT))

def time_until_next_epoch():
    millis_per_epoch = int(SLOTS_PER_EPOCH) * int(config.SECONDS_PER_SLOT) * 1000
    millis_from_genesis = round(time.time_ns() // 1_000_000) - int(config.MIN_GENESIS_TIME) * 1000

    if millis_from_genesis >= 0:
        return millis_per_epoch - (millis_from_genesis % millis_per_epoch)
    else:
        return abs(millis_from_genesis % millis_per_epoch)