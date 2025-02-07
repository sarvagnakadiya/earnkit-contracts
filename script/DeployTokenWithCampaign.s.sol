// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {Earnkit} from "../src/Earnkit.sol";
import {EarnkitToken} from "../src/Earnkit_token.sol";
import {console} from "forge-std/console.sol";

contract DeployTokenWithCampaign is Script {
    address constant WETH = 0x4200000000000000000000000000000000000006;
    uint24 constant FEE = 10000;
    int24 constant TICK = -230400;

    function generateSaltForAddress(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint256 fid,
        string memory image,
        string memory castHash,
        Earnkit.PoolConfig memory poolConfig,
        address deployer,
        address earnkitContract
    ) internal view returns (bytes32 salt) {
        uint256 saltNum = uint256(blockhash(block.number - 1)); // Start with a random number based on previous block hash
        // uint256 saltNum = 0;
        while (true) {
            bytes32 saltBytes = bytes32(saltNum);

            // Get the creation code for EarnkitToken
            bytes memory creationCode = type(EarnkitToken).creationCode;

            // Encode constructor parameters
            bytes memory constructorArgs = abi.encode(
                name,
                symbol,
                totalSupply,
                deployer,
                fid,
                image,
                castHash
            );

            // Combine creation code and constructor args
            bytes memory bytecode = abi.encodePacked(
                creationCode,
                constructorArgs
            );

            // Calculate the hash of the bytecode
            bytes32 bytecodeHash = keccak256(bytecode);

            // Calculate salt hash
            bytes32 saltHash = keccak256(abi.encode(deployer, saltBytes));

            // Calculate the token address using CREATE2 formula
            address predictedAddress = address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                earnkitContract,
                                saltHash,
                                bytecodeHash
                            )
                        )
                    )
                )
            );

            if (uint160(predictedAddress) < uint160(poolConfig.pairedToken)) {
                return saltBytes;
            }
            saltNum++;
        }
    }

    function run(address earnkitContract) external {
        // Load deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Configure pool settings
        Earnkit.PoolConfig memory poolConfig = Earnkit.PoolConfig({
            pairedToken: WETH,
            devBuyFee: FEE,
            tick: TICK
        });

        // Token parameters
        string memory name = "Sarvagna";
        string memory symbol = "SKK";
        uint256 totalSupply = 100_000_000_000 * 1e18; // 100B total supply
        uint256 fid = 884823;
        string
            memory image = "https://sarvagna.sqrtlabs.com/assets/1-9c390b40.png";
        string memory castHash = "0x9ecb8361a98711a1ecf36d8fbc391d1af9140ded";

        // Generate valid salt
        bytes32 salt = generateSaltForAddress(
            name,
            symbol,
            totalSupply,
            fid,
            image,
            castHash,
            poolConfig,
            deployer,
            earnkitContract
        );

        console.log("Generated salt:", uint256(salt));

        // Configure campaign settings
        Earnkit.CampaignInfo[] memory campaigns = new Earnkit.CampaignInfo[](2);

        // First campaign: 50M tokens per claim, 100 max claims
        campaigns[0] = Earnkit.CampaignInfo({
            maxClaims: 100,
            amountPerClaim: 50_000_000 * 1e18,
            maxSponsoredClaims: 0
        });

        // Second campaign: 25M tokens per claim, 200 max claims
        campaigns[1] = Earnkit.CampaignInfo({
            maxClaims: 200,
            amountPerClaim: 25_000_000 * 1e18,
            maxSponsoredClaims: 0
        });

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // use the earnkit contract address
        Earnkit earnkit = Earnkit(earnkitContract);

        // Cast the returned token address to address
        (EarnkitToken tokenContract, uint256 positionId) = earnkit
            .deployTokenWithCampaigns(
                name,
                symbol,
                totalSupply,
                FEE,
                salt,
                deployer,
                fid,
                image,
                castHash,
                poolConfig,
                campaigns,
                10 // 10% of total supply for campaigns
            );

        address token = address(tokenContract);

        console.log("Token deployed at:", token);
        console.log("Position ID:", positionId);

        vm.stopBroadcast();
    }
}
