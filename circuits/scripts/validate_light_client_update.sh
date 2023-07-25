#!/bin/bash

PHASE1=`realpath ../pot25_final.ptau`
BUILD_DIR=`realpath ../build`
CIRCUIT_NAME=assert_valid_signed_header
OUTPUT_DIR=`realpath "$BUILD_DIR"/"$CIRCUIT_NAME"_cpp`

run() {
    echo "****Executing witness generation****"
    start=`date +%s`
    "$OUTPUT_DIR"/"$CIRCUIT_NAME" ../../data/input_valid_signed_header.json "$OUTPUT_DIR"/witness.wtns
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****Converting witness to json****"
    start=`date +%s`
    npx snarkjs wej "$OUTPUT_DIR"/witness.wtns "$OUTPUT_DIR"/witness.json
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****GENERATING PROOF FOR SAMPLE INPUT****"
    start=`date +%s`
    "../../resources/rapidsnark/build/prover" "$OUTPUT_DIR"/"$CIRCUIT_NAME"_p2.zkey "$OUTPUT_DIR"/witness.wtns "$OUTPUT_DIR"/"$CIRCUIT_NAME"_proof.json "$OUTPUT_DIR"/"$CIRCUIT_NAME"_public.json
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****VERIFYING PROOF FOR SAMPLE INPUT****"
    start=`date +%s`
    npx snarkjs groth16 verify "$OUTPUT_DIR"/"$CIRCUIT_NAME"_vkey.json "$OUTPUT_DIR"/"$CIRCUIT_NAME"_public.json "$OUTPUT_DIR"/"$CIRCUIT_NAME"_proof.json
    end=`date +%s`
    echo "DONE ($((end-start))s)"
}

mkdir -p logs
run 2>&1 | tee logs/"$CIRCUIT_NAME"_$(date '+%Y-%m-%d-%H-%M').log
