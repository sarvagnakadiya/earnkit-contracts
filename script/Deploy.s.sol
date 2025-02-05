// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {Earnkit} from "../src/Earnkit.sol";
import {LpLocker} from "../src/LpLocker.sol";
import {console} from "forge-std/console.sol";
contract DeployEarnkit is Script {
    // Base Mainnet addresses
    // address constant UNISWAP_V3_FACTORY =
    //     0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    // address constant POSITION_MANAGER =
    //     0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    // address constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;

    // Base Sepolia addresses
    address constant UNISWAP_V3_FACTORY =
        0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address constant POSITION_MANAGER =
        0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2;
    address constant SWAP_ROUTER = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 teamReward = vm.envUint("TEAM_REWARD_PERCENTAGE");
        address teamRecipient = vm.envAddress("TEAM_RECIPIENT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy LpLocker first
        LpLocker locker = new LpLocker(
            teamRecipient,
            teamReward,
            POSITION_MANAGER
        );

        // Deploy Earnkit
        Earnkit earnkit = new Earnkit(
            address(locker),
            UNISWAP_V3_FACTORY,
            POSITION_MANAGER,
            SWAP_ROUTER,
            owner
        );

        // Update the factory address in LpLocker
        locker.updateEarnkitFactory(address(earnkit));

        // Transfer ownership of LpLocker to owner
        // locker.transferOwnership(owner);

        vm.stopBroadcast();

        console.log("Deployed Earnkit to:", address(earnkit));
        console.log("Deployed LpLocker to:", address(locker));
    }
}
