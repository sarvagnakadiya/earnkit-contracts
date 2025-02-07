#!/bin/bash
source .env

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