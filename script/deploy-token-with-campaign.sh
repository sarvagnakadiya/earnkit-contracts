#!/bin/bash

# Load environment variables
source .env

# Deploy the token with campaigns
forge script script/DeployTokenWithCampaign.s.sol:DeployTokenWithCampaign \
    --rpc-url $RPC_URL \
    --broadcast \
    -vvvv \
    --sig "run(address)" \
    ${EARNKIT_CONTRACT_ADDRESS} \