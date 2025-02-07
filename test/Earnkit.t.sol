// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Earnkit} from "../src/Earnkit.sol";
import {EarnkitToken} from "../src/Earnkit_token.sol";
import {LpLocker} from "../src/LpLocker.sol";
import {Campaigns} from "../src/coinvise/campaign.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProtocolRewards} from "../src/coinvise/protocol-rewards/ProtocolRewards.sol";
import {console} from "forge-std/console.sol";

contract EarnkitTest is Test {
    Earnkit public earnkit;
    LpLocker public lpLocker;
    Campaigns public campaigns;
    address public owner;
    address public admin;
    address public deployer;
    ProtocolRewards public protocolRewards;

    // Constants for testing
    uint24 constant FEE = 10000;
    int24 constant TICK = -230400;
    uint256 constant INITIAL_SUPPLY = 100000000000000000000000000000;

    // Base Mainnet Addresses
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant UNISWAP_V3_FACTORY =
        0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address constant POSITION_MANAGER =
        0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    uint256 constant BASE_FORK_BLOCK = 7300000;
    uint256 teamReward = vm.envUint("TEAM_REWARD_PERCENTAGE");
    address teamRecipient = vm.envAddress("TEAM_RECIPIENT_ADDRESS");
    address aiAgentRecipient = vm.envAddress("AI_AGENT_RECIPIENT_ADDRESS");
    uint256 aiAgentReward = vm.envUint("AI_AGENT_REWARD_PERCENTAGE");

    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork(vm.rpcUrl("base"), BASE_FORK_BLOCK);

        owner = makeAddr("owner");
        admin = makeAddr("admin");
        deployer = makeAddr("deployer");

        // Fund accounts with ETH
        vm.deal(owner, 100 ether);
        vm.deal(admin, 100 ether);
        vm.deal(deployer, 100 ether);

        vm.startPrank(owner);

        // Deploy core contracts with real addresses
        lpLocker = new LpLocker(
            owner,
            teamReward,
            POSITION_MANAGER,
            aiAgentRecipient,
            aiAgentReward
        );
        protocolRewards = new ProtocolRewards();
        console.log("protocolRewards address:", address(protocolRewards));

        campaigns = new Campaigns(
            owner, // trustedAddress
            0.00015 ether, // claimFee
            address(protocolRewards)
        );

        earnkit = new Earnkit(
            address(lpLocker),
            UNISWAP_V3_FACTORY,
            POSITION_MANAGER,
            SWAP_ROUTER,
            owner
        );
        lpLocker.updateEarnkitFactory(address(earnkit));

        // Setup permissions
        earnkit.setAdmin(admin, true);
        earnkit.toggleAllowedPairedToken(WETH, true);

        vm.stopPrank();
    }

    function generateSaltForAddress(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint256 fid,
        string memory image,
        string memory castHash,
        Earnkit.PoolConfig memory poolConfig
    ) internal view returns (bytes32 salt) {
        uint256 saltNum = 0;
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
                                address(earnkit),
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

    function test_deployToken() public {
        vm.startPrank(owner);

        // Add debug logs for WETH address
        console.log("WETH address:", WETH);

        Earnkit.PoolConfig memory poolConfig = Earnkit.PoolConfig({
            pairedToken: WETH,
            devBuyFee: FEE,
            tick: TICK
        });

        bytes32 salt = generateSaltForAddress(
            "spiderbhau",
            "SPIDYBHAI",
            INITIAL_SUPPLY,
            884823,
            "https://imagedelivery.net/BXluQx4ige9GuW0Ia56BHw/e275b813-d6fe-4adb-c9cf-89ff852b2300/original",
            "0xf8861c633e16c5abb11cd5e9dad7ae469115ded0",
            poolConfig
        );

        console.log("deploying token with salt:", uint256(salt));

        (EarnkitToken token, uint256 positionId) = earnkit.deployToken(
            "spiderbhau",
            "SPIDYBHAI",
            INITIAL_SUPPLY,
            FEE,
            salt,
            deployer,
            884823,
            "https://imagedelivery.net/BXluQx4ige9GuW0Ia56BHw/e275b813-d6fe-4adb-c9cf-89ff852b2300/original",
            "0xf8861c633e16c5abb11cd5e9dad7ae469115ded0",
            poolConfig
        );

        console.log("Actual token address:", address(token));
        console.log("Position ID:", positionId);
        vm.stopPrank();
    }

    function test_deployTokenWithCampaigns() public {
        vm.startPrank(admin);

        Earnkit.PoolConfig memory poolConfig = Earnkit.PoolConfig({
            pairedToken: WETH,
            devBuyFee: FEE,
            tick: TICK
        });

        bytes32 salt = generateSaltForAddress(
            "Test Token",
            "TEST",
            INITIAL_SUPPLY,
            1,
            "",
            "",
            poolConfig
        );

        // Create campaign configurations
        Earnkit.CampaignInfo[]
            memory campaignInfos = new Earnkit.CampaignInfo[](2);

        // Adjust campaign amounts for new total supply (10% of 100B = 10B tokens)
        uint256 campaign1Amount = 50000000 * 1e18; // 50M tokens per claim
        uint256 campaign2Amount = 25000000 * 1e18; // 25M tokens per claim

        campaignInfos[0] = Earnkit.CampaignInfo({
            maxClaims: 100,
            amountPerClaim: campaign1Amount,
            maxSponsoredClaims: 0
        });

        campaignInfos[1] = Earnkit.CampaignInfo({
            maxClaims: 200,
            amountPerClaim: campaign2Amount,
            maxSponsoredClaims: 0
        });

        // Calculate total campaign amounts
        uint256 totalCampaign1 = campaign1Amount * 100; // 5B tokens
        uint256 totalCampaign2 = campaign2Amount * 200; // 5B tokens
        uint256 totalCampaignTokens = totalCampaign1 + totalCampaign2; // 10B tokens (10% of total)

        // Ensure total campaign amounts equals 10% of supply
        assertEq(totalCampaignTokens, (INITIAL_SUPPLY * 10) / 100);

        uint256 initialEth = 1 ether;

        (EarnkitToken token, uint256 positionId) = earnkit
            .deployTokenWithCampaigns{value: initialEth}(
            "Test Token",
            "TEST",
            INITIAL_SUPPLY,
            FEE,
            salt,
            deployer,
            1, // fid
            "", // image
            "", // castHash
            poolConfig,
            address(campaigns),
            campaignInfos,
            10
        );

        // Verify token deployment
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.totalSupply(), INITIAL_SUPPLY);

        // Verify position was created
        assertTrue(positionId > 0);

        // Verify campaigns received exactly 10% of total supply
        assertEq(token.balanceOf(address(campaigns)), totalCampaignTokens);

        vm.stopPrank();
    }

    // function test_deployTokenWithCampaigns_RevertIfNotAdmin() public {
    //     Earnkit.PoolConfig memory poolConfig = Earnkit.PoolConfig({
    //         pairedToken: WETH,
    //         devBuyFee: FEE,
    //         tick: TICK
    //     });

    //     Earnkit.CampaignInfo[]
    //         memory campaignInfos = new Earnkit.CampaignInfo[](1);
    //     campaignInfos[0] = Earnkit.CampaignInfo({
    //         maxClaims: 100,
    //         amountPerClaim: 5000 * 1e18,
    //         maxSponsoredClaims: 10
    //     });

    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             Earnkit.NotOwnerOrAdmin.selector,
    //             address(this)
    //         )
    //     );

    //     earnkit.deployTokenWithCampaigns(
    //         "Test Token",
    //         "TEST",
    //         INITIAL_SUPPLY,
    //         FEE,
    //         bytes32(0),
    //         deployer,
    //         1,
    //         "",
    //         "",
    //         poolConfig,
    //         address(campaigns),
    //         campaignInfos
    //     );
    // }

    // function test_deployTokenWithCampaigns_RevertIfInvalidPairedToken() public {
    //     vm.startPrank(admin);

    //     // Create a random token that's not allowed
    //     address randomToken = makeAddr("randomToken");

    //     Earnkit.PoolConfig memory poolConfig = Earnkit.PoolConfig({
    //         pairedToken: randomToken,
    //         devBuyFee: 3000,
    //         tick: TICK
    //     });

    //     Earnkit.CampaignInfo[]
    //         memory campaignInfos = new Earnkit.CampaignInfo[](1);
    //     campaignInfos[0] = Earnkit.CampaignInfo({
    //         maxClaims: 100,
    //         amountPerClaim: 5000 * 1e18,
    //         maxSponsoredClaims: 10
    //     });

    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             Earnkit.NotAllowedPairedToken.selector,
    //             randomToken
    //         )
    //     );

    //     earnkit.deployTokenWithCampaigns(
    //         "Test Token",
    //         "TEST",
    //         INITIAL_SUPPLY,
    //         FEE,
    //         bytes32(0),
    //         deployer,
    //         1,
    //         "",
    //         "",
    //         poolConfig,
    //         address(campaigns),
    //         campaignInfos
    //     );

    //     vm.stopPrank();
    // }
}
