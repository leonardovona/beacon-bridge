# Beacon Relay
Proof of concept implementation of a relay between the Ethereum Beacon Chain and an EVM-based blockchain.

The relay is composed by two entities:
- An on-chain light client in the form of a composition of smart contracts deployed in the destination chain (EVM-based blockchain).
- An off-chain relayer responsible for retrieving block headers from the source chain (the Beacon Chain) and forwarding them to the destination one.

The on-chain light client validates incoming block headers by resembling the [light client specification](https://github.com/ethereum/annotated-spec/blob/master/altair/sync-protocol.md) of the Beacon Chain.

The BLS signature verification is outsourced by the light client into a zkSNARK circuit written in circom. The circuit is executed by the off-chain relayer at each block header submission. The resulting zero-knowledge proof is coupled with the block header and sent to the destination chain for validation.

## Requirements
- Node.js
- Python
- If you want to deploy the light client on a local blockchain, a tool such as [Ganache](https://github.com/trufflesuite/ganache)
- At least 200 GB of RAM for zkSNARK circuit compilation
- [snarkjs](https://github.com/iden3/snarkjs)
- A [powers of tau file](https://github.com/iden3/snarkjs#:~:text=NOTE-,Ptau%20files,-for%20bn128%20with) (at least power 25) for zkSNARK circuit setup
- [circom](https://docs.circom.io/)
- [circom-pairing](https://github.com/yi-sun/circom-pairing)
- [rapidsnark](https://github.com/iden3/rapidsnark)

## How to run
- Compile the zkSNARK circuits by executing the `init_rotate.sh` and `init_sync.sh` scripts located at `circuits\scripts`
- Deploy the light client to an EVM-based blockchain
- Execute `relay.py`

## Disclaimer
The code has not been audited and is not intended for production.
