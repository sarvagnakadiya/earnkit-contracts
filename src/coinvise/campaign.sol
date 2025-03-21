// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/* solhint-disable max-line-length */

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {RewardsSplitter} from "./protocol-rewards/RewardsSplitter.sol";

/* solhint-enable max-line-length */

/// @title Campaigns
/// @author Coinvise
/// @notice Create ERC20 token / native currency campaigns that are claimable with a signature from a trusted address
contract Campaigns is Ownable, ReentrancyGuard, EIP712, RewardsSplitter {
    using SafeERC20 for IERC20;

    /// @notice Emitted when trying to set `claimFee` to zero
    error InvalidFee();

    /// @notice Emitted when trying to create campaign with zero `_maxClaims` or `_amountPerClaim`
    error InvalidCount();

    /// @notice Emitted when incorrect msg.value is passed during purchase or renewal
    error IncorrectValue();

    /// @notice Emitted when trying to claim non existent campaign
    error NonExistentCampaign();

    /// @notice Emitted when trying to claim or withdraw an inactive campaign
    error InactiveCampaign();

    /// @notice Emitted when user tries to claim campaign more than once
    error AlreadyClaimed();

    /// @notice Emitted when user tries to claim a campaign that's fully claimed
    error ExceedsMaxClaims();

    /// @notice Emitted when ether transfer reverted
    error TransferFailed();

    /// @notice Emitted when `campaignManager` creates a campaign with `campaignId`
    /// @param campaignManager creator of the campaign
    /// @param campaignId id of the campaign created under the creator address
    event CampaignCreated(
        address indexed campaignManager,
        uint256 indexed campaignId
    );

    /// @notice Emitted when `campaignManager` withdraws  a campaign with `campaignId`
    /// @param campaignManager creator of the campaign
    /// @param campaignId id of the campaign being withdrawn
    event CampaignWithdrawn(
        address indexed campaignManager,
        uint256 indexed campaignId
    );

    /// @notice Emitted when `claimer` claims a campaign by `campaignManager` with `campaignId`
    /// @param campaignManager creator of the campaign
    /// @param campaignId id of the campaign being claimed
    /// @param claimer address of the claimer
    /// @param tokenAddress address of token being claimed
    /// @param amount amount of tokens being claimed
    event CampaignClaimed(
        address indexed campaignManager,
        uint256 indexed campaignId,
        address indexed claimer,
        address tokenAddress,
        uint256 amount
    );

    /// @notice Emitted when fees are withdrawn to `treasury`
    /// @param amount amount of funds withdrawn to `treasury`
    /// @param treasury treasury address to which funds are withdrawn
    event Withdrawal(uint256 amount, address indexed treasury);

    /// @notice Emitted when sponsored claim fees are paid during createCampaign
    /// @param sponsoredClaims number of sponsored claims
    /// @param claimFee sponsored claim fees paid
    /// @param claimFeeRecipient sponsored claim fee recipient
    event SponsoredClaimFeesPaid(
        uint256 sponsoredClaims,
        uint256 claimFee,
        address claimFeeRecipient
    );

    /// @notice Emitted when mint fee is paid during mint
    /// @param claimFee claim fee paid
    /// @param claimFeePayer token claimer who paid claimFee
    /// @param claimFeeRecipient claim fee recipient
    /// @param campaignManager campaignManager of campaign
    /// @param campaignId campaignId of campaign
    /// @param referrer referrer of token claimer
    event ClaimFeePaid(
        uint256 claimFee,
        address claimFeePayer,
        address claimFeeRecipient,
        address campaignManager,
        uint256 campaignId,
        address referrer
    );

    struct Campaign {
        address tokenAddress; // address of token used in campaign
        uint256 maxClaims; // max no. of claims possible for the campaign
        uint256 noOfClaims; // no. of times a campaign has been claimed
        uint256 amountPerClaim; // amount of tokens received per claim
        uint256 isInactive; // whether campaign has been withdrawn, and is now inactive
        uint256 maxSponsoredClaims; // max allowed sponsored mints
        uint256 noOfSponsoredClaims; // no. of sponsored claims
    }

    /// @dev ETH pseudo-address used to represent native currency campaigns
    address private constant ETHAddress =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    bytes32 private constant _CLAIM_TYPEHASH =
        keccak256(
            "Claim(address campaignManager,uint256 campaignId,address claimer)"
        );

    /// @dev Address used for signatures
    address internal trustedAddress;

    /// @notice Claim Fee
    uint256 public claimFee;

    /// @notice Total claim fees accrued that is withdrawable
    uint256 public totalClaimFees;

    /// @notice Mapping to store next campaignId for a user: campaignManager => campaignId
    /// @dev    campaignId is only unique to each campaignManager, not global
    mapping(address => uint256) internal nextCampaignId;

    /// @notice Mapping to store campaigns: campaignManager => campaignId => Campaign
    /// @dev Helps avoid writing repeated campaignManager addresses in storage.
    ///      campaignId is only unique to each campaignManager, not global
    mapping(address => mapping(uint256 => Campaign)) public campaigns;

    /// @notice Mapping to store addresses who've claimed a campaign:
    ///         keccak256(abi.encode(campaignManager, campaignId, claimer)) => claimed
    /// @dev    Helps avoid multiple hashing & inputs for nested mapping
    mapping(bytes32 => uint256) public hasClaimed;

    /// @notice Sponsored Claim Fee
    uint256 public sponsoredClaimFee;

    /// @notice Treasury address
    /// @dev Receives sponsored claim fees during createCampaign
    address public treasury;

    constructor(
        address _trustedAddress,
        uint256 _claimFee,
        address _protocolRewards
    )
        Ownable(msg.sender)
        EIP712("Campaigns", "1.0")
        RewardsSplitter(_protocolRewards)
    {
        if (_trustedAddress == address(0)) revert InvalidAddress();
        trustedAddress = _trustedAddress;
        claimFee = _claimFee;
    }

    /// @notice Create a new campaign
    /// @dev Stores a new `Campaign` to `campaigns[campaignManager][campaignId]`.
    ///      Transfers the total required tokens from creator to contract.
    ///      Reverts if `_tokenAddress` or `_campaignManager` is zero.
    ///      Reverts if `_maxClaims` | `_amountPerClaim` is not greater than zero.
    ///      Emits `CampaignCreated`
    /// @param _campaignManager address of the campaign manager
    /// @param _tokenAddress address of token used in campaign
    /// @param _maxClaims max no. of claims possible for the campaign
    /// @param _amountPerClaim amount of tokens received per claim
    /// @param _maxSponsoredClaims no. of sponsored claims
    function createCampaign(
        address _campaignManager,
        address _tokenAddress,
        uint256 _maxClaims,
        uint256 _amountPerClaim,
        uint256 _maxSponsoredClaims
    ) external payable nonReentrant returns (uint256 _campaignId) {
        // Revert if InvalidAddress / InvalidCount
        if (_tokenAddress == address(0) || _campaignManager == address(0))
            revert InvalidAddress();
        if (_maxClaims == 0 || _amountPerClaim == 0) revert InvalidCount();
        if (_maxSponsoredClaims > _maxClaims) revert ExceedsMaxClaims();

        // Create & store new Campaign
        /// @dev practically hard for nextCampaignId to overflow type(uint256).max
        unchecked {
            _campaignId = nextCampaignId[_campaignManager]++;
            Campaign storage _campaign = campaigns[_campaignManager][
                _campaignId
            ];
            _campaign.tokenAddress = _tokenAddress;
            _campaign.maxClaims = _maxClaims;
            _campaign.noOfClaims = 0;
            _campaign.amountPerClaim = _amountPerClaim;
            _campaign.isInactive = 0;
            _campaign.maxSponsoredClaims = _maxSponsoredClaims;
            _campaign.noOfSponsoredClaims = 0;
        }

        uint256 totalValue;
        uint256 totalSponsoredClaimFees = _maxSponsoredClaims *
            sponsoredClaimFee;
        uint256 totalCampaignAmount = _amountPerClaim * _maxClaims;
        if (_tokenAddress != ETHAddress) {
            IERC20(_tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                totalCampaignAmount
            );
            totalValue = totalSponsoredClaimFees;
        } else {
            totalValue = totalSponsoredClaimFees + totalCampaignAmount;
        }
        if (msg.value != totalValue) revert IncorrectValue();

        if (totalSponsoredClaimFees > 0) {
            _paySponsoredClaimFees(_maxSponsoredClaims);
        }

        // Emit event
        assembly {
            log3(
                0x00,
                0x00, // no data
                0xfc5b9d1c2c1134048e1792e3ae27d4eee04f460d341711c7088000d2ca218621, // CampaignCreated(address,uint256)
                _campaignManager, // campaignManager (changed from caller())
                _campaignId // campaignId
            )
        }

        return _campaignId;
    }

    /// @notice Claim a campaign
    /// @dev Transfers campaign.amountPerClaim tokens to claimer.
    ///      Reverts if
    ///       - campaign does not exist.
    ///       - campaign is inactive.
    ///       - claimer has already claimed before.
    ///       - campaign is fully claimed.
    ///       - `claimFee` is not paid.
    ///       - signature verification fails.
    ///      Emits `CampaignClaimed`
    /// @param _campaignManager creator of the campaign to claim
    /// @param _campaignId id of the campaign to claim. unique to campaignManager, not global
    /// @param r r component of claim signature from `trustedAddress`
    /// @param s s component of claim signature from `trustedAddress`
    /// @param v v component of claim signature from `trustedAddress`
    /// @param _referrer referrer for the claim
    function claim(
        address _campaignManager,
        uint256 _campaignId,
        bytes32 r,
        bytes32 s,
        uint8 v,
        address _referrer
    ) external payable nonReentrant {
        if (msg.sender == _referrer) revert InvalidAddress();

        Campaign storage _campaign = campaigns[_campaignManager][_campaignId];

        if (_campaign.tokenAddress == address(0)) revert NonExistentCampaign();
        if (_campaign.isInactive != 0) revert InactiveCampaign();

        bytes32 _hasClaimedKey = keccak256(
            abi.encode(_campaignManager, _campaignId, msg.sender)
        );
        if (hasClaimed[_hasClaimedKey] != 0) revert AlreadyClaimed();
        if (_campaign.noOfClaims == _campaign.maxClaims)
            revert ExceedsMaxClaims();

        // Check claimFee paid
        // Don't charge if sponsored claims are available
        bool _isSponsoredClaim = _campaign.noOfSponsoredClaims <
            _campaign.maxSponsoredClaims;
        uint256 _claimFee = _isSponsoredClaim ? 0 : claimFee;
        if (msg.value != _claimFee) revert InvalidFee();
        if (_claimFee > 0) {
            _payClaimFee(_claimFee, _campaignManager, _campaignId, _referrer);
        }
        if (_isSponsoredClaim) {
            _campaign.noOfSponsoredClaims++;
        }

        // Verify signature
        if (
            ECDSA.recover(
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            _CLAIM_TYPEHASH,
                            _campaignManager,
                            _campaignId,
                            msg.sender
                        )
                    )
                ),
                v,
                r,
                s
            ) != trustedAddress
        ) {
            revert InvalidAddress();
        }

        // Update Campaign state (before external calls)
        /// @dev Practically hard for this to overflow type(uint256).max
        ///      Max value for noOfClaims is maxClaims which has max value type(uint256).max
        unchecked {
            _campaign.noOfClaims++;
        }
        hasClaimed[_hasClaimedKey] = 1;
        totalClaimFees += msg.value;

        address _tokenAddress = _campaign.tokenAddress;
        uint256 _amountPerClaim = _campaign.amountPerClaim;

        emit CampaignClaimed(
            _campaignManager,
            _campaignId,
            msg.sender,
            _tokenAddress,
            _amountPerClaim
        );

        // Transfer tokens
        _transferFunds(_tokenAddress, msg.sender, _amountPerClaim);
    }

    /// @notice Withdraw / Cancel a campaign
    /// @dev Marks campaign as inactive.
    ///      Transfers remaining tokens of the campaign to the creator
    ///      Reverts if campaign does not exist.
    ///      Reverts if campaign is inactive
    ///      Emits `CampaignWithdrawn`
    /// @param _campaignId id of the campaign being withdrawn / cancelled
    function withdrawCampaign(uint256 _campaignId) external nonReentrant {
        Campaign storage _campaign = campaigns[msg.sender][_campaignId];

        if (_campaign.tokenAddress == address(0)) revert NonExistentCampaign();
        if (_campaign.isInactive != 0) revert InactiveCampaign();

        // Mark as inactive
        _campaign.isInactive = 1;

        // Emit event
        /* emit CampaignWithdrawn(msg.sender, _campaignId); */
        assembly {
            log3(
                0x00,
                0x00, // no data
                0x06a0982d8b0bd87e1ae43f31a116ca52b1353fbc3dc30a1a97cf143da800cb0d, // CampaignWithdrawn(address,uint256)
                caller(), // campaignManager
                _campaignId // campaignId
            )
        }

        // Transfer remaining tokens
        _transferFunds(
            _campaign.tokenAddress,
            msg.sender,
            (_campaign.maxClaims - _campaign.noOfClaims) *
                _campaign.amountPerClaim
        );
    }

    /// @notice Increase no. of sponsored claims
    /// @dev Reverts if exceeds max claims
    /// @param _additionalSponsoredClaims Number to increase current sponsored claims by
    function increaseMaxSponsoredClaims(
        address _campaignManager,
        uint256 _campaignId,
        uint256 _additionalSponsoredClaims
    ) external payable nonReentrant {
        Campaign storage _campaign = campaigns[_campaignManager][_campaignId];

        uint256 newSponsoredClaims = _campaign.maxSponsoredClaims +
            _additionalSponsoredClaims;
        if (newSponsoredClaims > _campaign.maxClaims) {
            revert ExceedsMaxClaims();
        }

        _campaign.maxSponsoredClaims = newSponsoredClaims;

        _paySponsoredClaimFees(_additionalSponsoredClaims);
    }

    /// @notice Withdraw total claim fees collected
    /// @dev Transfers `totalClaimFees` to `_treasury` iff it is > 0
    ///      Callable only by `owner`.
    ///      Emits `Withdrawal`
    /// @param _treasury treasury address to which funds are withdrawn
    function withdrawTotalClaimFees(
        address _treasury
    ) external payable onlyOwner nonReentrant {
        uint256 amount = totalClaimFees;

        if (amount > 0) {
            // reset totalClaimFees
            totalClaimFees = 0;

            assembly {
                /* emit Withdrawal(amount, _treasury); */
                let memPtr := mload(64)
                mstore(memPtr, amount)
                log2(
                    memPtr,
                    32, // _amount
                    0xd964a27d45f595739c13d8b1160b57491050cacf3a2e5602207277d6228f64ee, // Withdrawal(uint256,address)
                    _treasury // treasury
                )

                // (bool success, ) = _treasury.call{ value: amount }("");
                // if (!success)
                if iszero(call(gas(), _treasury, amount, 0, 0, 0, 0)) {
                    mstore(0x00, 0x90b8ec18) // revert TransferFailed();
                    revert(0x1c, 0x04)
                }
            }
        }
    }

    /// @notice Set `trustedAddress`
    /// @dev Callable only by `owner`.
    ///      Reverts if `_trustedAddress` is address(0).
    /// @param _trustedAddress Address to be used for signatures
    function setTrustedAddress(
        address _trustedAddress
    ) external payable onlyOwner {
        if (_trustedAddress == address(0)) revert InvalidAddress();
        trustedAddress = _trustedAddress;
    }

    /// @notice Set `treasury`
    /// @dev Callable only by `owner`.
    ///      Reverts if `_treasury` is address(0).
    /// @param _treasury Address to be used for signatures
    function setTreasury(address _treasury) external payable onlyOwner {
        if (_treasury == address(0)) revert InvalidAddress();
        treasury = _treasury;
    }

    /// @notice Set `claimFee`
    /// @dev Callable only by `owner`.
    /// @param _claimFee Claim fee
    function setClaimFee(uint256 _claimFee) external payable onlyOwner {
        assembly {
            sstore(claimFee.slot, _claimFee) // claimFee = _claimFee;
        }
    }

    /// @notice Set `sponsoredClaimFee`
    /// @dev Callable only by `owner`.
    /// @param _sponsoredClaimFee Claim fee
    function setSponsoredClaimFee(
        uint256 _sponsoredClaimFee
    ) external payable onlyOwner {
        assembly {
            sstore(sponsoredClaimFee.slot, _sponsoredClaimFee) // sponsoredClaimFee = _sponsoredClaimFee;
        }
    }

    /// @dev Internal function to pay claim fee
    ///      Splits and deposits into protocol rewards
    ///      Emits ClaimFeePaid
    function _payClaimFee(
        uint256 _claimFee,
        address _campaignManager,
        uint256 _campaignId,
        address _referrer
    ) internal {
        splitAndDepositRewards(
            _claimFee,
            treasury, // platform
            _campaignManager, // creator
            _referrer // referrer
        );

        emit ClaimFeePaid(
            _claimFee,
            msg.sender,
            treasury,
            _campaignManager,
            _campaignId,
            _referrer
        );
    }

    /// @dev Internal function to pay sponsored claim fees
    ///      Emits SponsoredClaimFeesPaid
    function _paySponsoredClaimFees(uint256 _sponsoredClaims) internal {
        uint256 totalSponsoredClaimFees = _sponsoredClaims * sponsoredClaimFee;

        // ensure sponsored claim fees is paid in current transaction
        if (msg.value < totalSponsoredClaimFees) {
            revert IncorrectValue();
        }

        _transferFunds(ETHAddress, treasury, totalSponsoredClaimFees);

        emit SponsoredClaimFeesPaid(
            _sponsoredClaims,
            sponsoredClaimFee,
            treasury
        );
    }

    /// @dev Utility method to handle ether or token transfers.
    ///      Reverts if transfer fails
    /// @param tokenAddress address of token to transfer
    /// @param recipient recipient of the ether / token transfer
    /// @param amount amount of ether / token to transfer in wei
    function _transferFunds(
        address tokenAddress,
        address recipient,
        uint256 amount
    ) internal {
        if (tokenAddress != ETHAddress) {
            IERC20(tokenAddress).safeTransfer(recipient, amount);
        } else {
            (bool success, ) = recipient.call{value: amount}("");
            if (!success) revert TransferFailed();
        }
    }
}
