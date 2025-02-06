// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {Campaigns} from "../src/coinvise/campaign.sol";
import {ProtocolRewards} from "../src/coinvise/protocol-rewards/ProtocolRewards.sol";

contract DeployCampaign is Script {
    ProtocolRewards public protocolRewards;
    Campaigns public campaigns;

    function run(
        address trustedAddress,
        uint256 claimFee,
        address treasury,
        uint256 sponsoredClaimFee
    ) public returns (Campaigns) {
        vm.startBroadcast();

        // Deploy ProtocolRewards
        protocolRewards = new ProtocolRewards();

        // Deploy Campaigns
        campaigns = new Campaigns(
            trustedAddress,
            claimFee,
            address(protocolRewards)
        );

        // Set up treasury and sponsored claim fee
        campaigns.setTreasury(treasury);
        campaigns.setSponsoredClaimFee(sponsoredClaimFee);

        vm.stopBroadcast();

        return campaigns;
    }
}
