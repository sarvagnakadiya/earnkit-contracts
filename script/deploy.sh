#!/bin/bash

# Load environment variables
source .env

# Check if required environment variables are set
if [ -z "$PRIVATE_KEY" ] || [ -z "$OWNER_ADDRESS" ] || [ -z "$TEAM_RECIPIENT_ADDRESS" ] || [ -z "$TEAM_REWARD_PERCENTAGE" ]; then
    echo "Error: Missing required environment variables"
    echo "Please make sure PRIVATE_KEY, OWNER_ADDRESS, TEAM_RECIPIENT_ADDRESS, and TEAM_REWARD_PERCENTAGE are set in .env"
    exit 1
fi

# Run the deployment script
forge script script/Deploy.s.sol:DeployAll \
    --rpc-url ${RPC_URL} \
    --verify \
    -vv \
    --via-ir

# Check if deployment was successful
if [ $? -eq 0 ]; then
    echo "Deployment completed successfully!"
else
    echo "Deployment failed!"
    exit 1
fi 