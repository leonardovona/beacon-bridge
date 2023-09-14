#!/bin/bash
PHASE1=../../resources/powersOfTau28_hez_final_27.ptau
CIRCUIT_NAME=step
BUILD_DIR=`realpath ../build/"$CIRCUIT_NAME"`
SNARKJS=`realpath ../../node_modules/.bin/snarkjs`

run() {
    if [ ! -d "$BUILD_DIR" ]; then
        echo "No build directory found. Creating build directory..."
        mkdir -p "$BUILD_DIR"
    fi

    echo "****COMPILING CIRCUIT****"
    circom ../"$CIRCUIT_NAME".circom --O1 --r1cs --sym --c --output "$BUILD_DIR"

    echo "****Running make to make witness generation binary****"
    make -C `"$BUILD_DIR"/"$CIRCUIT_NAME"_cpp`

    echo "****GENERATING ZKEY 0****"
    node --max-old-space-size=2048000 $SNARKJS zkey new "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PHASE1" "$OUTPUT_DIR"/"$CIRCUIT_NAME"_p1.zkey

    echo "****CONTRIBUTE TO PHASE 2 CEREMONY****"
    node $SNARKJS zkey contribute "$OUTPUT_DIR"/"$CIRCUIT_NAME"_p1.zkey "$OUTPUT_DIR"/"$CIRCUIT_NAME"_p2.zkey -n="First phase2 contribution" -e="some random text for entropy"

    echo "****EXPORTING VKEY****"
    npx $SNARKJS zkey export verificationkey "$OUTPUT_DIR"/"$CIRCUIT_NAME"_p2.zkey "$OUTPUT_DIR"/"$CIRCUIT_NAME"_vkey.json

    echo "****EXPORTING SOLIDITY SMART CONTRACT****"
    npx $SNARKJS zkey export solidityverifier "$OUTPUT_DIR"/"$CIRCUIT_NAME"_p2.zkey "$CIRCUIT_NAME"_verifier.sol
}

mkdir -p logs
run 2>&1 | tee logs/"$CIRCUIT_NAME"_$(date '+%Y-%m-%d-%H-%M').log
