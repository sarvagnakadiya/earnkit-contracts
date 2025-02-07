// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Campaigns} from "../src/coinvise/campaign.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {RewardsSplitter} from "../src/coinvise/protocol-rewards/RewardsSplitter.sol";
import {DeployCampaign} from "../script/DeployCampaign.s.sol";
import {console} from "forge-std/console.sol";

contract CampaignTest is Test {
    Campaigns public campaigns;
    MockERC20 public token;
    DeployCampaign deployer;

    address public TRUSTED_ADDRESS = vm.envAddress("TRUSTED_ADDRESS");
    address public TREASURY = vm.envAddress("TREASURY_ADDRESS");
    uint256 public CLAIM_FEE = vm.envUint("CLAIM_FEE");
    uint256 public SPONSORED_CLAIM_FEE = vm.envUint("SPONSORED_CLAIM_FEE");

    // Using a known private key for testing
    uint256 public TRUSTED_SIGNER_PRIVATE_KEY =
        vm.envUint("TRUSTED_SIGNER_PRIVATE_KEY");

    // Address that will sign campaign claims
    address public campaignManager;
    address public claimer;

    bytes32 private constant _CLAIM_TYPEHASH =
        keccak256(
            "Claim(address campaignManager,uint256 campaignId,address claimer)"
        );

    function setUp() public {
        // Setup accounts
        campaignManager = makeAddr("campaignManager");
        claimer = makeAddr("claimer");
        vm.deal(claimer, 1 ether); // Give claimer some ETH for claim fees
        vm.deal(campaignManager, 1 ether); // Give campaign manager ETH for creating campaigns

        // Deploy all contracts using the deployment script
        deployer = new DeployCampaign();
        campaigns = deployer.run(
            TRUSTED_ADDRESS,
            CLAIM_FEE,
            TREASURY,
            SPONSORED_CLAIM_FEE
        );

        // Deploy test token
        token = new MockERC20("Test Token", "TEST");

        // Setup campaign manager
        token.mint(campaignManager, 1000 ether);
        vm.startPrank(campaignManager);
        token.approve(address(campaigns), type(uint256).max);
        vm.stopPrank();

        // Add debug logging
        console.log("Campaign contract:", address(campaigns));
        console.log("Token contract:", address(token));
        console.log("Campaign manager:", campaignManager);
        console.log("Claimer:", claimer);
        console.log("Treasury:", TREASURY);
        console.log("Claim fee:", CLAIM_FEE);
        console.log("Sponsored claim fee:", SPONSORED_CLAIM_FEE);
        console.log("Protocol rewards:", address(deployer.protocolRewards()));
    }

    function testCreateAndClaimCampaign() public {
        // Add balance checks before campaign creation
        console.log("Campaign manager ETH balance:", campaignManager.balance);
        console.log(
            "Campaign manager token balance:",
            token.balanceOf(campaignManager)
        );
        console.log(
            "Token allowance:",
            token.allowance(campaignManager, address(campaigns))
        );

        // Campaign parameters
        uint256 maxClaims = 100;
        uint256 amountPerClaim = 1 ether;
        uint256 maxSponsoredClaims = 0;

        // Create campaign
        vm.startPrank(campaignManager);
        console.log("Creating campaign");

        // Create campaign with proper value for sponsored claims
        uint256 campaignId = campaigns.createCampaign{value: 0}(
            campaignManager,
            address(token),
            maxClaims,
            amountPerClaim,
            maxSponsoredClaims
        );
        console.log("Campaign created with id:", campaignId);
        vm.stopPrank();

        // Get campaign details to verify
        (address tokenAddress, uint256 actualMaxClaims, , , , , ) = campaigns
            .campaigns(campaignManager, campaignId);

        // Verify campaign creation
        assertEq(tokenAddress, address(token), "Wrong token address");
        assertEq(actualMaxClaims, maxClaims, "Wrong max claims");

        console.log("Claimer balance before claim:", token.balanceOf(claimer));

        // Generate signature for claim
        bytes32 domainSeparator = _calculateDomainSeparator();
        bytes32 structHash = keccak256(
            abi.encode(_CLAIM_TYPEHASH, campaignManager, campaignId, claimer)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            TRUSTED_SIGNER_PRIVATE_KEY,
            digest
        );

        // Record balances before claim
        uint256 claimerBalanceBefore = token.balanceOf(claimer);

        // Claim campaign
        vm.prank(claimer);
        campaigns.claim{value: CLAIM_FEE}(
            campaignManager,
            campaignId,
            r,
            s,
            v,
            address(0) // no referrer
        );

        console.log("Claimed campaign!!!");
        console.log("Claimed campaign amount:", token.balanceOf(claimer));

        console.log(
            "Protocol Rewards ETH Balance:",
            address(deployer.protocolRewards()).balance
        );

        // Verify claim
        assertEq(
            token.balanceOf(claimer),
            claimerBalanceBefore + amountPerClaim,
            "Incorrect claim amount received"
        );
        // verify protocol rewards balance
        assertEq(
            address(deployer.protocolRewards()).balance,
            CLAIM_FEE,
            "Incorrect protocol rewards balance"
        );

        // Get treasury balance before withdrawal
        uint256 treasuryBalanceBefore = TREASURY.balance;

        // Withdraw rewards to treasury
        vm.prank(TREASURY); // Only treasury can withdraw its own rewards
        deployer.protocolRewards().withdrawRewards(payable(TREASURY));

        console.log(
            "Protocol Rewards ETH Balance after withdrawal:",
            address(deployer.protocolRewards()).balance
        );
        console.log("Treasury ETH Balance after withdrawal:", TREASURY.balance);

        // Verify treasury received the claim fee
        assertEq(
            TREASURY.balance,
            treasuryBalanceBefore + 105000000000000,
            "Treasury did not receive correct claim fee"
        );

        console.log(
            "Campaign manager ETH balance before:",
            campaignManager.balance
        );

        uint256 campaignManagerBalanceBefore = campaignManager.balance;

        vm.prank(campaignManager); // Only treasury can withdraw its own rewards
        deployer.protocolRewards().withdrawRewards(payable(campaignManager));

        assertEq(
            campaignManager.balance,
            campaignManagerBalanceBefore + 45000000000000,
            "Campaign manager did not receive correct claim fee"
        );
        console.log(
            "Campaign manager ETH balance after:",
            campaignManager.balance
        );
        // console.log(
        //     "Protocol Rewards ETH Balance after withdrawal of manager:",
        //     address(deployer.protocolRewards()).balance
        // );

        // Verify protocol rewards contract balance is now 0
        assertEq(
            address(deployer.protocolRewards()).balance,
            0,
            "Protocol rewards contract should have 0 balance after withdrawal"
        );
    }

    function _calculateDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("Campaigns")),
                    keccak256(bytes("1.0")),
                    block.chainid,
                    address(campaigns)
                )
            );
    }
}
