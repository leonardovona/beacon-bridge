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
async function convert_sync_committee(b: number = 512) {
  const dirname = path.resolve();
  const rawData = fs.readFileSync(
    path.join(dirname, "data/syncCommittee.json")
  );
  const syncCommittee = JSON.parse(rawData.toString());

  const pubkeys = syncCommittee.pubkeys.map((pubkey: any, idx: number) => {
    const point = PointG1.fromHex((pubkey).substring(2));
    const bigints = point_to_bigint(point);
    return [
      bigint_to_array(n, k, bigints[0]),
      bigint_to_array(n, k, bigints[1]),
    ];
  });

  const pubkeysHex = syncCommittee.pubkeys.map((pubkey: any, idx: number) => {
    return hexToIntArray(pubkey);
  });

  const aggregatePubkeyHex = hexToIntArray(syncCommittee.aggregatePubkey)

  const syncCommitteeConverted = {
    pubkeys: pubkeys,
    pubkeyHex: pubkeysHex,
    aggregatePubkeyHex : aggregatePubkeyHex
  };

  const syncCommitteeFilename = path.join(
    dirname,
    "data",
    `input_sync_committee_committments.json`
  );
  
  console.log("Writing input to file", syncCommitteeFilename);
  fs.writeFileSync(
    syncCommitteeFilename,
    JSON.stringify(syncCommitteeConverted)
  );
}

convert_sync_committee();
