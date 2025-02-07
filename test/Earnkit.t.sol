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
    address public TREASURY = vm.envAddress("TREASURY_ADDRESS");
    address public TRUSTED_ADDRESS = vm.envAddress("TRUSTED_ADDRESS");
    uint256 public TRUSTED_SIGNER_PRIVATE_KEY =
        vm.envUint("TRUSTED_SIGNER_PRIVATE_KEY");

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
            TRUSTED_ADDRESS, // trustedAddress
            0.00015 ether, // claimFee
            address(protocolRewards)
        );

        campaigns.setTreasury(TREASURY);

        earnkit = new Earnkit(
            address(lpLocker),
            UNISWAP_V3_FACTORY,
            POSITION_MANAGER,
            SWAP_ROUTER,
            owner,
            address(campaigns)
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

    function _calculateDomainSeparator(
        address campaignsAddress
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("Campaigns")),
                    keccak256(bytes("1.0")),
                    block.chainid,
                    campaignsAddress
                )
            );
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

        // Stop admin prank before starting claim tests
        vm.stopPrank();

        // Setup claimer
        address claimer = makeAddr("claimer");
        vm.deal(claimer, 1 ether); // Give claimer some ETH for claim fees

        // Generate signature for claim
        bytes32 domainSeparator = _calculateDomainSeparator(address(campaigns));
        bytes32 _CLAIM_TYPEHASH = keccak256(
            "Claim(address campaignManager,uint256 campaignId,address claimer)"
        );

        bytes32 structHash = keccak256(
            abi.encode(_CLAIM_TYPEHASH, deployer, 0, claimer) // campaignId 0 for first campaign
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            TRUSTED_SIGNER_PRIVATE_KEY,
            digest
        );

        bytes32 structHash2 = keccak256(
            abi.encode(_CLAIM_TYPEHASH, deployer, 1, claimer) // campaignId 1 for second campaign
        );

        bytes32 digest2 = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash2)
        );

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            TRUSTED_SIGNER_PRIVATE_KEY,
            digest2
        );

        // Record balances before claim
        uint256 claimerBalanceBefore = token.balanceOf(claimer);
        uint256 campaignsBalanceBefore = token.balanceOf(address(campaigns));

        // Perform claim
        vm.startPrank(claimer);
        campaigns.claim{value: 0.00015 ether}(deployer, 0, r, s, v, address(0));
        campaigns.claim{value: 0.00015 ether}(
            deployer,
            1,
            r2,
            s2,
            v2,
            address(0)
        );
        vm.stopPrank();

        // Verify claim amounts
        assertEq(
            token.balanceOf(claimer),
            claimerBalanceBefore + campaign1Amount + campaign2Amount,
            "Claimer did not receive correct amount"
        );
        assertEq(
            token.balanceOf(address(campaigns)),
            campaignsBalanceBefore - campaign1Amount - campaign2Amount,
            "Campaigns contract balance not reduced correctly"
        );

        // Try claiming again - should revert
        vm.expectRevert(abi.encodeWithSignature("AlreadyClaimed()"));
        vm.prank(claimer);
        campaigns.claim{value: 0.00015 ether}(deployer, 0, r, s, v, address(0));

        // Try claiming with wrong fee - should revert
        address newClaimer = makeAddr("newClaimer");
        vm.deal(newClaimer, 1 ether);

        vm.expectRevert(abi.encodeWithSignature("InvalidFee()"));
        vm.prank(newClaimer);
        campaigns.claim{value: 0.0001 ether}(deployer, 0, r, s, v, address(0)); // Wrong fee amount
    }

    // revert tests
    function test_deployTokenWithCampaigns_RevertIfNotAdmin() public {
        Earnkit.PoolConfig memory poolConfig = Earnkit.PoolConfig({
            pairedToken: WETH,
            devBuyFee: FEE,
            tick: TICK
        });

        Earnkit.CampaignInfo[]
            memory campaignInfos = new Earnkit.CampaignInfo[](1);
        campaignInfos[0] = Earnkit.CampaignInfo({
            maxClaims: 100,
            amountPerClaim: 5000 * 1e18,
            maxSponsoredClaims: 10
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                Earnkit.NotOwnerOrAdmin.selector,
                address(this)
            )
        );

        earnkit.deployTokenWithCampaigns(
            "Test Token",
            "TEST",
            INITIAL_SUPPLY,
            FEE,
            bytes32(0),
            deployer,
            1,
            "",
            "",
            poolConfig,
            campaignInfos,
            10
        );
    }

    function test_deployTokenWithCampaigns_RevertIfInvalidPairedToken() public {
        vm.startPrank(admin);

        // Create a random token that's not allowed
        address randomToken = makeAddr("randomToken");

        Earnkit.PoolConfig memory poolConfig = Earnkit.PoolConfig({
            pairedToken: randomToken,
            devBuyFee: 3000,
            tick: TICK
        });

        Earnkit.CampaignInfo[]
            memory campaignInfos = new Earnkit.CampaignInfo[](1);
        campaignInfos[0] = Earnkit.CampaignInfo({
            maxClaims: 100,
            amountPerClaim: 5000 * 1e18,
            maxSponsoredClaims: 10
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                Earnkit.NotAllowedPairedToken.selector,
                randomToken
            )
        );

        earnkit.deployTokenWithCampaigns(
            "Test Token",
            "TEST",
            INITIAL_SUPPLY,
            FEE,
            bytes32(0),
            deployer,
            1,
            "",
            "",
            poolConfig,
            campaignInfos,
            10
        );

        vm.stopPrank();
    }

    function test_deployToken_MultipleDeployments() public {
        vm.startPrank(owner);

        Earnkit.PoolConfig memory poolConfig = Earnkit.PoolConfig({
            pairedToken: WETH,
            devBuyFee: FEE,
            tick: TICK
        });

        // First deployment
        bytes32 salt1 = generateSaltForAddress(
            "Test Token 1",
            "TEST1",
            INITIAL_SUPPLY,
            1,
            "",
            "",
            poolConfig
        );

        (EarnkitToken token1, uint256 positionId1) = earnkit.deployToken(
            "Test Token 1",
            "TEST1",
            INITIAL_SUPPLY,
            FEE,
            salt1,
            deployer,
            1,
            "",
            "",
            poolConfig
        );
        console.log("token1 address:", address(token1));

        // Second deployment with SAME parameters but different salt will succeed
        // Because generateSaltForAddress uses block.number in salt generation
        vm.roll(block.number + 1); // Move to next block to get different salt
        bytes32 salt2 = generateSaltForAddress(
            "Test Token 1",
            "TEST1",
            INITIAL_SUPPLY,
            1,
            "",
            "",
            poolConfig
        );

        // This should succeed because we have a different salt
        (EarnkitToken token2, uint256 positionId2) = earnkit.deployToken(
            "Test Token 1",
            "TEST1",
            INITIAL_SUPPLY,
            FEE,
            salt2,
            deployer,
            1,
            "",
            "",
            poolConfig
        );
        console.log("token2 address:", address(token2));

        // Verify we got different addresses
        assertTrue(
            address(token1) != address(token2),
            "Tokens should have different addresses"
        );

        // Now try with same salt as first deployment - this should fail
        // vm.expectRevert("CREATE2 failed");
        // earnkit.deployToken(
        //     "Test Token 1",
        //     "TEST1",
        //     INITIAL_SUPPLY,
        //     FEE,
        //     salt1, // Using first salt again
        //     deployer,
        //     1,
        //     "",
        //     "",
        //     poolConfig
        // );

        vm.stopPrank();
    }
}
