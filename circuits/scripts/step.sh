#!/bin/bash
PHASE1=../../resources/powersOfTau28_hez_final_27.ptau
CIRCUIT_NAME=step
BUILD_DIR=`realpath ../build/"$CIRCUIT_NAME"`
SNARKJS=`realpath ../../node_modules/.bin/snarkjs`
INPUT=`realpath ../../data/input_"$CIRCUIT_NAME".json`
PROVER=`realpath ../../resources/rapidsnark/build/prover`

run() {
    echo "****Executing witness generation****"
    "$BUILD_DIR"/"$CIRCUIT_NAME"_cpp/"$CIRCUIT_NAME" $INPUT "$BUILD_DIR"/witness.wtns

    echo "****Converting witness to json****"
    npx $SNARKJS wej "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/witness.json

    echo "****GENERATING PROOF FOR SAMPLE INPUT****"
    $PROVER "$BUILD_DIR"/"$CIRCUIT_NAME"_p2.zkey "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/"$CIRCUIT_NAME"_proof.json "$BUILD_DIR"/"$CIRCUIT_NAME"_public.json
}

mkdir -p logs
run 2>&1 | tee logs/"$CIRCUIT_NAME"_$(date '+%Y-%m-%d-%H-%M').log
