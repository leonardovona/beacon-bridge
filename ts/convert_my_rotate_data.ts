/* 
* Adapted from: https://github.com/succinctlabs/eth-proof-of-consensus/blob/main/circuits/test/generate_input_data.ts
*/
import path from "path";
import fs from "fs";

import { PointG1 } from "@noble/bls12-381";

import {
  bigint_to_array,
  hexToIntArray,
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
* Convert sync committee to a suitable format for sync committee committment verification circuit.
* Pubkeys are converted first to G1 points and then to bigints.
* The input data is taken from a file in the data folder.
* The output is written to a file in the data folder.
*/
async function convert_my_rotate_data(b: number = 512) {
  const dirname = path.resolve();
  const rawData = fs.readFileSync(
    path.join(dirname, "data/my_rotate_data.json")
  );
  const myRotateData = JSON.parse(rawData.toString());

  const pubkeys = myRotateData.pubkeys.map((pubkey: any, idx: number) => {
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

  const syncCommitteeBranch = myRotateData.syncCommitteeBranch.map((element: any, idx: number) => {
    return hexToIntArray(element);
  });

  const myRotateDataConverted = {
    pubkeysBigIntX: pubkeysBigIntX,
    pubkeysBigIntY: pubkeysBigIntY, 
    syncCommitteeSSZ: hexToIntArray(myRotateData.syncCommitteeSSZ),
    syncCommitteeBranch: syncCommitteeBranch,
    syncCommitteePoseidon: myRotateData.syncCommitteePoseidon,
    finalizedHeaderRoot: hexToIntArray(myRotateData.finalizedHeaderRoot),
    finalizedSlot: hexToIntArray(myRotateData.finalizedSlot),
    finalizedProposerIndex: hexToIntArray(myRotateData.finalizedProposerIndex),
    finalizedParentRoot: hexToIntArray(myRotateData.finalizedParentRoot),
    finalizedStateRoot: hexToIntArray(myRotateData.finalizedStateRoot),
    finalizedBodyRoot: hexToIntArray(myRotateData.finalizedBodyRoot)
  };

  const myRotateDataFilename = path.join(
    dirname,
    "data",
    `input_sync_committee_committments.json`
  );
  
  console.log("Writing input to file", myRotateDataFilename);
  fs.writeFileSync(
    myRotateDataFilename,
    JSON.stringify(myRotateDataConverted)
  );
}

convert_my_rotate_data();
