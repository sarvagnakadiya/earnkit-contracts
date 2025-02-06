// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {NonFungibleContract, ILocker} from "./Interfaces/ILpLocker.sol";

/// @title LpLocker
/// @notice Contract for managing LP token positions and reward distribution
/// @dev Handles LP token locking and reward collection from Uniswap V3 positions
contract LpLocker is Ownable, IERC721Receiver, ILocker {
    // Custom errors
    error ExceedsMaxBps();
    error NotAllowed(address user);
    error InvalidTokenId(uint256 tokenId);
    error InvalidRewardPercentage();

    // Constants
    uint256 private constant MAX_BPS = 100;

    // Events
    event Received(address indexed from, uint256 indexed tokenId);
    event ClaimedRewards(
        address indexed claimer,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 totalAmount0,
        uint256 totalAmount1
    );

    // Structs
    struct UserRewardRecipient {
        address recipient;
        uint256 lpTokenId;
    }

    struct TeamRewardRecipient {
        address recipient;
        uint256 reward;
        uint256 lpTokenId;
    }

    // Immutable state variables
    address public immutable positionManager;

    // Storage variables
    IERC721 private safeERC721;
    address private immutable e721Token;
    uint256 private earnkitTeamReward;
    address private earnkitTeamRecipient;
    address public factory;
    uint256 private aiAgentReward;
    address private aiAgentRecipient;

    // Mappings
    mapping(uint256 => UserRewardRecipient) public userRewardRecipientForToken;
    mapping(uint256 => TeamRewardRecipient)
        public teamOverrideRewardRecipientForToken;
    mapping(address => uint256[]) public userTokenIds;

    // Modifiers
    modifier validateBps(uint256 _bps) {
        if (_bps > MAX_BPS) revert ExceedsMaxBps();
        _;
    }

    /// @notice Contract constructor
    /// @param _earnkitTeamRecipient Address to receive team portion of fees
    /// @param _earnkitTeamRewardBps Team reward percentage
    /// @param _positionManagerAddr Address of Uniswap V3 position manager
    /// @param _aiAgentRecipient Address to receive AI agent portion of fees
    /// @param _aiAgentRewardBps AI agent reward percentage
    constructor(
        address _earnkitTeamRecipient,
        uint256 _earnkitTeamRewardBps,
        address _positionManagerAddr,
        address _aiAgentRecipient,
        uint256 _aiAgentRewardBps
    ) Ownable(_earnkitTeamRecipient) {
        earnkitTeamReward = _earnkitTeamRewardBps;
        earnkitTeamRecipient = _earnkitTeamRecipient;
        positionManager = _positionManagerAddr;
        aiAgentRecipient = _aiAgentRecipient;
        aiAgentReward = _aiAgentRewardBps;
    }

    /// @notice Set override team rewards for a specific token
    /// @param _tokenId Token ID to set override for
    /// @param _newTeamRecipient New team recipient address
    /// @param _newTeamReward New team reward percentage
    function setOverrideTeamRewardsForToken(
        uint256 _tokenId,
        address _newTeamRecipient,
        uint256 _newTeamReward
    ) public onlyOwner validateBps(_newTeamReward) {
        if (_newTeamReward + aiAgentReward > MAX_BPS) {
            revert InvalidRewardPercentage();
        }
        teamOverrideRewardRecipientForToken[_tokenId] = TeamRewardRecipient({
            recipient: _newTeamRecipient,
            reward: _newTeamReward,
            lpTokenId: _tokenId
        });
    }

    /// @notice Update the factory contract address
    /// @param _newFactory New factory contract address
    function updateEarnkitFactory(address _newFactory) public onlyOwner {
        factory = _newFactory;
    }

    /// @notice Update the team reward percentage
    /// @param _newReward New reward percentage
    function updateEarnkitTeamReward(
        uint256 _newReward
    ) public onlyOwner validateBps(_newReward) {
        if (_newReward + aiAgentReward > MAX_BPS) {
            revert InvalidRewardPercentage();
        }
        earnkitTeamReward = _newReward;
    }

    /// @notice Update the team recipient address
    /// @param _newRecipient New recipient address
    function updateEarnkitTeamRecipient(
        address _newRecipient
    ) public onlyOwner {
        earnkitTeamRecipient = _newRecipient;
    }

    /// @notice Update the AI agent recipient address
    /// @param _newRecipient New recipient address
    function updateAiAgentRecipient(address _newRecipient) public onlyOwner {
        aiAgentRecipient = _newRecipient;
    }

    /// @notice Update the AI agent reward percentage
    /// @param _newReward New reward percentage
    function updateAiAgentReward(
        uint256 _newReward
    ) public onlyOwner validateBps(_newReward) {
        if (_newReward + earnkitTeamReward > MAX_BPS) {
            revert InvalidRewardPercentage();
        }
        aiAgentReward = _newReward;
    }

    /// @notice Withdraw ETH from the contract
    /// @param _recipient Address to receive the ETH
    function withdrawETH(address _recipient) public onlyOwner {
        payable(_recipient).transfer(address(this).balance);
    }

    /// @notice Withdraw ERC20 tokens from the contract
    /// @param _token Token address to withdraw
    /// @param _recipient Address to receive the tokens
    function withdrawERC20(
        address _token,
        address _recipient
    ) public onlyOwner {
        IERC20 token = IERC20(_token);
        token.transfer(_recipient, token.balanceOf(address(this)));
    }

    /// @notice Collect rewards from a Uniswap V3 position
    /// @param _tokenId Token ID of the position
    function collectRewards(uint256 _tokenId) public override {
        UserRewardRecipient
            memory userRewardRecipient = userRewardRecipientForToken[_tokenId];
        address recipient = userRewardRecipient.recipient;

        if (recipient == address(0)) revert InvalidTokenId(_tokenId);

        NonFungibleContract nonfungiblePositionManager = NonFungibleContract(
            positionManager
        );

        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.collect(
            NonFungibleContract.CollectParams({
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max,
                tokenId: _tokenId
            })
        );

        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(_tokenId);

        IERC20 rewardToken0 = IERC20(token0);
        IERC20 rewardToken1 = IERC20(token1);

        // Cache variables for gas efficiency
        address teamRecipient = earnkitTeamRecipient;
        uint256 teamReward = earnkitTeamReward;
        address aiRecipient = aiAgentRecipient;
        uint256 aiReward = aiAgentReward;

        TeamRewardRecipient
            memory overrideRewardRecipient = teamOverrideRewardRecipientForToken[
                _tokenId
            ];

        if (overrideRewardRecipient.recipient != address(0)) {
            teamRecipient = overrideRewardRecipient.recipient;
            teamReward = overrideRewardRecipient.reward;
        }

        // Calculate rewards for each party
        uint256 protocolReward0 = (amount0 * teamReward) / 100;
        uint256 protocolReward1 = (amount1 * teamReward) / 100;

        uint256 aiAgentReward0 = (amount0 * aiReward) / 100;
        uint256 aiAgentReward1 = (amount1 * aiReward) / 100;

        uint256 recipientReward0 = amount0 - protocolReward0 - aiAgentReward0;
        uint256 recipientReward1 = amount1 - protocolReward1 - aiAgentReward1;

        // Transfer rewards to each party
        rewardToken0.transfer(recipient, recipientReward0);
        rewardToken1.transfer(recipient, recipientReward1);

        rewardToken0.transfer(teamRecipient, protocolReward0);
        rewardToken1.transfer(teamRecipient, protocolReward1);

        rewardToken0.transfer(aiRecipient, aiAgentReward0);
        rewardToken1.transfer(aiRecipient, aiAgentReward1);

        emit ClaimedRewards(
            recipient,
            token0,
            token1,
            recipientReward0,
            recipientReward1,
            amount0,
            amount1
        );
    }

    /// @notice Get all LP token IDs for a user
    /// @param _user Address of the user
    /// @return Array of token IDs
    function getLpTokenIdsForUser(
        address _user
    ) public view returns (uint256[] memory) {
        return userTokenIds[_user];
    }

    /// @notice Add a new user reward recipient
    /// @param _recipient Recipient information to add
    function addUserRewardRecipient(
        UserRewardRecipient memory _recipient
    ) public {
        if (msg.sender != owner() && msg.sender != factory)
            revert NotAllowed(msg.sender);
        userRewardRecipientForToken[_recipient.lpTokenId] = _recipient;
        userTokenIds[_recipient.recipient].push(_recipient.lpTokenId);
    }

    /// @notice Replace an existing user reward recipient
    /// @param _recipient New recipient information
    function replaceUserRewardRecipient(
        UserRewardRecipient memory _recipient
    ) public {
        UserRewardRecipient memory oldRecipient = userRewardRecipientForToken[
            _recipient.lpTokenId
        ];

        if (msg.sender != owner() && msg.sender != oldRecipient.recipient) {
            revert NotAllowed(msg.sender);
        }

        delete userRewardRecipientForToken[_recipient.lpTokenId];

        uint256[] memory tokenIds = userTokenIds[_recipient.recipient];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (tokenIds[i] == _recipient.lpTokenId) {
                delete userTokenIds[_recipient.recipient][i];
            }
        }

        userRewardRecipientForToken[_recipient.lpTokenId] = _recipient;
        userTokenIds[_recipient.recipient].push(_recipient.lpTokenId);
    }

    /// @notice Handle receipt of ERC721 token
    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address,
        address _from,
        uint256 _id,
        bytes calldata
    ) external override returns (bytes4) {
        if (_from != factory) {
            revert NotAllowed(_from);
        }

        emit Received(_from, _id);
        return IERC721Receiver.onERC721Received.selector;
    }
}
