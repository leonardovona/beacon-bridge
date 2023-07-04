
from utils.specs import (
    Slot, SLOTS_PER_EPOCH, config
)
import time, math


def get_current_slot(tolerance=0):
    """
    Return the current slot
    Tolerance is used to account for clock drift
    """
    diff_in_seconds = time.time() - config.MIN_GENESIS_TIME + tolerance
    return Slot(math.floor(diff_in_seconds / config.SECONDS_PER_SLOT))


def time_until_next_epoch():
    """
    Return the number of seconds until the next epoch starts
    """
    millis_per_epoch = int(SLOTS_PER_EPOCH) * int(config.SECONDS_PER_SLOT) * 1000
    millis_from_genesis = round(time.time_ns() // 1_000_000) - int(config.MIN_GENESIS_TIME) * 1000

    if millis_from_genesis >= 0:
        return (millis_per_epoch - (millis_from_genesis % millis_per_epoch)) / 1000
    else:
        return abs((millis_from_genesis % millis_per_epoch)) / 1000