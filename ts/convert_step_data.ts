/* 
* Adapted from: https://github.com/succinctlabs/eth-proof-of-consensus/blob/main/circuits/test/generate_input_data.ts
*/
import path from "path";
import fs from "fs";

import { PointG1 } from "@noble/bls12-381";

import {
  hexToIntArray,
  bigint_to_array,
  sigHexAsSnarkInput,
  msg_hash
} from "./bls_utils";

(BigInt.prototype as any).toJSON = function () {
  return this.toString();
};

var n: number = 55;
var k: number = 7;

function point_to_bigint(point: PointG1): [bigint, bigint] {
  let [x, y] = point.toAffine();
  return [x.value, y.value];
}

/*
* Convert data to a suitable format for signature verification circuit.
* Pubkeys are converted first to G1 points and then to bigints.
* A similar process is followed for the signature and the signing root.
* The input data is taken from a file in the data folder.
* The output is written to a file in the data folder.
*/
async function convertStepData(b: number = 512) {
  const dirname = path.resolve();
  const rawData = fs.readFileSync(
    path.join(dirname, "data/step_data.json")
  );
  const stepData = JSON.parse(rawData.toString());

  const pubkeys = stepData.pubkeys.map((pubkey: any, idx: number) => {
    const point = PointG1.fromHex((pubkey).substring(2));
    const bigints = point_to_bigint(point);
    return [
      bigint_to_array(n, k, bigints[0]),
      bigint_to_array(n, k, bigints[1]),
    ];
  });

  const pubkeysBigIntX = new Array<Array<number>>();
  const pubkeysBigIntY = new Array<Array<number>>();

  for(let i = 0; i < pubkeys.length; i++) {
    pubkeysBigIntX.push(pubkeys[i][0]);
    pubkeysBigIntY.push(pubkeys[i][1]);
  }

  const outputData = {
    pubkeysBigIntX: pubkeysBigIntX,
    pubkeysBigIntY: pubkeysBigIntY,
    aggregationBits: stepData.pubkeybits,
    signature: sigHexAsSnarkInput(stepData.signature, "array"),
    signingRoot: hexToIntArray(stepData.signingRoot),
    participation: stepData.participation,
    syncCommitteePoseidon: stepData.syncCommitteePoseidon,
  };

  const outputFilename = path.join(
    dirname,
    "data",
    `input_step.json`
  );
  
  console.log("Writing input to file", outputFilename);
  fs.writeFileSync(
    outputFilename,
    JSON.stringify(outputData)
  );
}

convertStepData();
