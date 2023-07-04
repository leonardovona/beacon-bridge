import path from "path";
import fs from "fs";

import { PointG1, aggregatePublicKeys } from "@noble/bls12-381";
import { toHexString } from "@chainsafe/ssz";

import {
  formatHex,
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

async function generate_data(b: number = 512) {
  const dirname = path.resolve();
  const rawData = fs.readFileSync(
    path.join(dirname, "data/syncCommittee.json")
  );
  const syncCommittee = JSON.parse(rawData.toString());

  let aggPubkey = PointG1.ZERO;
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

generate_data();
