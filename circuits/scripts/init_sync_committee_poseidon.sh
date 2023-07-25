#!/bin/bash
PHASE1=../../resources/powersOfTau28_hez_final_27.ptau
CIRCUIT_NAME=sync_committee_poseidon
BUILD_DIR=`realpath ../$CIRCUIT_NAME`
CPP_DIR=`realpath "$BUILD_DIR"/"$CIRCUIT_NAME"_cpp`
SNARKJS=`realpath ../../ts/node_modules/.bin/snarkjs`

run() {
    if [ ! -d "$BUILD_DIR" ]; then
        echo "No build directory found. Creating build directory..."
        mkdir -p "$BUILD_DIR"
    fi

    echo "****COMPILING CIRCUIT****"
    start=`date +%s`
    circom ../"$CIRCUIT_NAME".circom --O1 --r1cs --sym --c --output "$BUILD_DIR"
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****Running make to make witness generation binary****"
    start=`date +%s`
    make -C "$CPP_DIR"
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****GENERATING ZKEY 0****"
    start=`date +%s`
    node --trace-gc --trace-gc-ignore-scavenger --max-old-space-size=2048000 --initial-old-space-size=2048000 --no-global-gc-scheduling --no-incremental-marking --max-semi-space-size=1024 --initial-heap-size=2048000 --expose-gc "$SNARKJS" zkey new "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PHASE1" "$BUILD_DIR"/"$CIRCUIT_NAME"_p1.zkey
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****CONTRIBUTE TO PHASE 2 CEREMONY****"
    start=`date +%s`
    node "$SNARKJS" zkey contribute "$BUILD_DIR"/"$CIRCUIT_NAME"_p1.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_p2.zkey -n="First phase2 contribution" -e="some random text for entropy"
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****EXPORTING VKEY****"
    start=`date +%s`
    npx "$SNARKJS" zkey export verificationkey "$BUILD_DIR"/"$CIRCUIT_NAME"_p2.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****EXPORTING SOLIDITY SMART CONTRACT****"
    start=`date +%s`
    npx "$SNARKJS" zkey export solidityverifier "$BUILD_DIR"/"$CIRCUIT_NAME"_p2.zkey "$BUILD_DIR$"/"$CIRCUIT_NAME"_verifier.sol
    end=`date +%s`
    echo "DONE ($((end-start))s)"
}

mkdir -p logs
run 2>&1 | tee logs/"$CIRCUIT_NAME"_$(date '+%Y-%m-%d-%H-%M').log
