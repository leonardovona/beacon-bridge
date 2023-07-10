/* 
* Adapted from: https://github.com/succinctlabs/eth-proof-of-consensus/blob/main/circuits/test/generate_input_data.ts
*/
import path from "path";
import fs from "fs";

import { PointG1 } from "@noble/bls12-381";

import {
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
* A similar process is followed for the signature and the signing root (Hm).
* The input data is taken from a file in the data folder.
* The output is written to a file in the data folder.
*/
async function convertValidSignedHeaderData(b: number = 512) {
  const dirname = path.resolve();
  const rawData = fs.readFileSync(
    path.join(dirname, "data/signature_verify.json")
  );
  const validSignedHeaderData = JSON.parse(rawData.toString());

  const pubkeys = validSignedHeaderData.pubkeys.map((pubkey: any, idx: number) => {
    const point = PointG1.fromHex((pubkey).substring(2));
    const bigints = point_to_bigint(point);
    return [
      bigint_to_array(n, k, bigints[0]),
      bigint_to_array(n, k, bigints[1]),
    ];
  });

  const validSignedHeaderConverted = {
    pubkeys: pubkeys,
    pubkeybits: validSignedHeaderData.pubkeybits,
    signature: sigHexAsSnarkInput(validSignedHeaderData.signature, "array"),
    Hm: await msg_hash(validSignedHeaderData.Hm, "array"),
  };

  const validSignedHeaderFilename = path.join(
    dirname,
    "data",
    `input_signature_verify.json`
  );
  
  console.log("Writing input to file", validSignedHeaderFilename);
  fs.writeFileSync(
    validSignedHeaderFilename,
    JSON.stringify(validSignedHeaderConverted)
  );
}

convertValidSignedHeaderData();
