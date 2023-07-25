#!/bin/bash
PHASE1=../../resources/powersOfTau28_hez_final_27.ptau
CIRCUIT_NAME=sync_committee_poseidon
BUILD_DIR=`realpath ../$CIRCUIT_NAME`
CPP_DIR=`realpath "$BUILD_DIR"/"$CIRCUIT_NAME"_cpp`
RAPIDSNARK=`realpath ../../resources/rapidsnark/build/prover`

run() {
    echo "****Executing witness generation****"
    start=`date +%s`
    "$CPP_DIR"/"$CIRCUIT_NAME" ../../data/input_"$CIRCUIT_NAME".json "$BUILD_DIR"/witness.wtns
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****GENERATING PROOF FOR SAMPLE INPUT****"
    start=`date +%s`
    "$RAPIDSNARK" "$BUILD_DIR"/"$CIRCUIT_NAME"_p2.zkey "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/"$CIRCUIT_NAME"_proof.json "$BUILD_DIR"/"$CIRCUIT_NAME"_public.json
    end=`date +%s`
    echo "DONE ($((end-start))s)"
}

mkdir -p logs
run 2>&1 | tee logs/"$CIRCUIT_NAME"_$(date '+%Y-%m-%d-%H-%M').log
