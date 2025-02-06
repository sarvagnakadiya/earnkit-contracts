#!/bin/bash
source .env

# Required parameters
# TRUSTED_ADDRESS="0x..."  # Address that can pause/unpause
# CLAIM_FEE="1000000000000000"  # 0.001 ETH in wei
# TREASURY_ADDRESS="0x..."  # Treasury address to receive fees
# SPONSORED_CLAIM_FEE="500000000000000"  # 0.0005 ETH in wei

# Deploy to specified network
forge script script/DeployCampaign.s.sol:DeployCampaign \
    --rpc-url ${RPC_URL} \
    --private-key ${PRIVATE_KEY} \
    --broadcast \
    --verify \
    --etherscan-api-key ${ETHERSCAN_API_KEY} \
    -vvvv \
    --sig "run(address,uint256,address,uint256)" \
    ${TRUSTED_ADDRESS} \
    ${CLAIM_FEE} \
    ${TREASURY_ADDRESS} \
    ${SPONSORED_CLAIM_FEE} 