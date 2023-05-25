from web3 import Web3, HTTPProvider
from solcx import install_solc, compile_source
import ast

if __name__ == "__main__":
    # install_solc('0.8.17')
    
    with open ('./contracts/lightClient.sol', 'r') as file:
        source = file.read()
        compiled_solc = compile_source(source, 
                                       output_values=['abi', 'bin'], 
                                       base_path='./contracts', 
                                       optimize=True, 
                                       optimize_runs=200,
                                       solc_version='0.8.17')
        web3 = Web3(HTTPProvider('http://localhost:7545', request_kwargs={'timeout': 300}))
        web3.eth.default_account = web3.eth.accounts[0]
        abi = compiled_solc['<stdin>:LightClient']['abi']
        bytecode = compiled_solc['<stdin>:LightClient']['bin']
        LightClient = web3.eth.contract(abi=abi, bytecode=bytecode)
        tx_hash = LightClient.constructor().transact({'gas': 100_000_000})
        tx_receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
        light_client = web3.eth.contract(address=tx_receipt.contractAddress, abi=abi)
    
        with open('./test/light_client_bootstrap.txt', 'r') as file:
            light_client_bootstrap = ast.literal_eval(file.read())
            tx_hash = light_client.functions.initializeLightClientStore(
                light_client_bootstrap,
                "0x8ecceab6f2301d0e8a649e858116c7b9fc826707b31b50f551499f680e9aa9ff"
            ).transact()
            tx_receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
            print(tx_receipt)
            
            print(light_client.functions.getStore().call().hex())

        with open('./test/genesis_validators_root.txt', 'r') as gvr_file, \
            open('./test/current_slot_0.txt', 'r') as cs_file, \
            open('./test/light_client_update_0.txt', 'r') as lcu_file:
            genesis_validators_root = gvr_file.read()
            current_slot = int(cs_file.read())
            light_client_update = ast.literal_eval(lcu_file.read())
            tx_hash = light_client.functions.processLightClientUpdate(
                light_client_update,
                current_slot,
                genesis_validators_root
            ).transact({'gas': 100_000_000})
            tx_receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
            print(tx_receipt)

            print(light_client.functions.getStore().call().hex())
