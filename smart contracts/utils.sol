pragma solidity ^0.8.17;

import "./constants.sol";

library Utils {
    // Math utilities
    // taken from https://medium.com/coinmonks/math-in-solidity-part-5-exponent-and-logarithm-9aef8515136e
    function log2(
        uint256 x, 
        bool ceil
    ) public pure returns (uint256 n) {
        if (x >= 2**128) {
            x >>= 128;
            n += 128;
        }
        if (x >= 2**64) {
            x >>= 64;
            n += 64;
        }
        if (x >= 2**32) {
            x >>= 32;
            n += 32;
        }
        if (x >= 2**16) {
            x >>= 16;
            n += 16;
        }
        if (x >= 2**8) {
            x >>= 8;
            n += 8;
        }
        if (x >= 2**4) {
            x >>= 4;
            n += 4;
        }
        if (x >= 2**2) {
            x >>= 2;
            n += 2;
        }
        if (x >= 2**1) {
            x >>= 1;
            n += 1;
        }
        if(ceil) {
            if (x >= 2**0) {
                n += 1;
            }
        }
    }

     // https://ethereum.stackexchange.com/questions/83626/how-to-reverse-byte-order-in-uint256-or-bytes32
    function reverse(uint256 input) public pure returns (uint256 v) {
        v = input;

        // swap bytes
        v =
            ((v &
                0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >>
                8) |
            ((v &
                0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) <<
                8);

        // swap 2-byte long pairs
        v =
            ((v &
                0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >>
                16) |
            ((v &
                0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) <<
                16);

        // swap 4-byte long pairs
        v =
            ((v &
                0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >>
                32) |
            ((v &
                0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) <<
                32);

        // swap 8-byte long pairs
        v =
            ((v &
                0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >>
                64) |
            ((v &
                0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) <<
                64);

        // swap 16-byte long pairs
        v = (v >> 128) | (v << 128);
    }

    function toBytes(uint64 a) public pure returns (bytes32) {
        return bytes32(reverse(uint256(a)));
    }
    
    // Clock utilities
    function computeEpochAtSlot(uint64 slot) public pure returns (uint64) {
        return slot / SLOTS_PER_EPOCH;
    }

    function computeSyncCommitteePeriod(
        uint64 epoch
    ) public pure returns (uint64) {
        return epoch / EPOCHS_PER_SYNC_COMMITTEE_PERIOD;
    }

    function computeSyncCommitteePeriodAtSlot(
        uint64 slot
    ) public pure returns (uint64) {
        return computeSyncCommitteePeriod(computeEpochAtSlot(slot));
    }  
}