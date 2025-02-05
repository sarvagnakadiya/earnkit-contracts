// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {NonFungibleContract, ILocker} from "./Interfaces/ILpLocker.sol";

contract LpLocker is Ownable, IERC721Receiver, ILocker {
    event Received(address indexed from, uint256 tokenId);

    error NotAllowed(address user);

    event ClaimedRewards(
        address indexed claimer,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 totalAmount1,
        uint256 totalAmount0
    );

    IERC721 private SafeERC721;
    address private immutable e721Token;
    address public immutable positionManager;
    uint256 public _earnkitTeamReward;
    address public _earnkitTeamRecipient;
    address public _factory;
    struct UserRewardRecipient {
        address recipient;
        uint256 lpTokenId;
    }

    struct TeamRewardRecipient {
        address recipient;
        uint256 reward;
        uint256 lpTokenId;
    }

    mapping(uint256 => UserRewardRecipient) public _userRewardRecipientForToken;
    mapping(uint256 => TeamRewardRecipient)
        public _teamOverrideRewardRecipientForToken;

    mapping(address => uint256[]) public _userTokenIds;

    constructor(
        address earnkitTeamRecipient, // earnkit team address to receive portion of the fees
        uint256 earnkitTeamReward, // earnkit team reward percentage
        address _positionManager
    ) Ownable(earnkitTeamRecipient) {
        _earnkitTeamReward = earnkitTeamReward;
        _earnkitTeamRecipient = earnkitTeamRecipient;
        positionManager = _positionManager;
    }

    function setOverrideTeamRewardsForToken(
        uint256 tokenId,
        address newTeamRecipient,
        uint256 newTeamReward
    ) public onlyOwner {
        _teamOverrideRewardRecipientForToken[tokenId] = TeamRewardRecipient({
            recipient: newTeamRecipient,
            reward: newTeamReward,
            lpTokenId: tokenId
        });
    }

    function updateEarnkitFactory(address newFactory) public onlyOwner {
        _factory = newFactory;
    }

    // Update the earnkit team reward
    function updateEarnkitTeamReward(uint256 newReward) public onlyOwner {
        _earnkitTeamReward = newReward;
    }

    // Update the earnkit team recipient
    function updateEarnkitTeamRecipient(address newRecipient) public onlyOwner {
        _earnkitTeamRecipient = newRecipient;
    }

    // Withdraw ETH from the contract
    function withdrawETH(address recipient) public onlyOwner {
        payable(recipient).transfer(address(this).balance);
    }

    // Withdraw ERC20 tokens from the contract
    function withdrawERC20(address _token, address recipient) public onlyOwner {
        IERC20 IToken = IERC20(_token);
        IToken.transfer(recipient, IToken.balanceOf(address(this)));
    }

    // Use collect rewards to collect the rewards
    function collectRewards(uint256 _tokenId) public override {
        // Get the _userRewardRecipients for the tokenId
        UserRewardRecipient
            memory userRewardRecipient = _userRewardRecipientForToken[_tokenId];

        address _recipient = userRewardRecipient.recipient;

        require(_recipient != address(0), "Invalid tokenId");

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

        // gas efficiency
        address teamRecipient = _earnkitTeamRecipient;
        uint256 teamReward = _earnkitTeamReward;

        TeamRewardRecipient
            memory overrideRewardRecipient = _teamOverrideRewardRecipientForToken[
                _tokenId
            ];

        if (overrideRewardRecipient.recipient != address(0)) {
            teamRecipient = overrideRewardRecipient.recipient;
            teamReward = overrideRewardRecipient.reward;
        }

        uint256 protocolReward0 = (amount0 * teamReward) / 100;
        uint256 protocolReward1 = (amount1 * teamReward) / 100;

        uint256 recipientReward0 = amount0 - protocolReward0;
        uint256 recipientReward1 = amount1 - protocolReward1;

        rewardToken0.transfer(_recipient, recipientReward0);
        rewardToken1.transfer(_recipient, recipientReward1);

        rewardToken0.transfer(teamRecipient, protocolReward0);
        rewardToken1.transfer(teamRecipient, protocolReward1);

        emit ClaimedRewards(
            _recipient,
            token0,
            token1,
            recipientReward0,
            recipientReward1,
            amount0,
            amount1
        );
    }

    function getLpTokenIdsForUser(
        address user
    ) public view returns (uint256[] memory) {
        return _userTokenIds[user];
    }

    function addUserRewardRecipient(
        UserRewardRecipient memory recipient
    ) public {
        require(
            msg.sender == owner() || msg.sender == _factory,
            "only owner or factory allowed to add user reward recipient"
        );
        _userRewardRecipientForToken[recipient.lpTokenId] = recipient;
        _userTokenIds[recipient.recipient].push(recipient.lpTokenId);
    }

    function replaceUserRewardRecipient(
        UserRewardRecipient memory recipient
    ) public {
        // Get the old recipient
        UserRewardRecipient memory oldRecipient = _userRewardRecipientForToken[
            recipient.lpTokenId
        ];

        // Only owner or recipient can replace the reward recipient
        if (msg.sender != owner() && msg.sender != oldRecipient.recipient) {
            revert NotAllowed(msg.sender);
        }

        // Remove the old recipient
        delete _userRewardRecipientForToken[recipient.lpTokenId];

        // Remove the old tokenId from _userTokenIds
        uint256[] memory tokenIds = _userTokenIds[recipient.recipient];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (tokenIds[i] == recipient.lpTokenId) {
                delete _userTokenIds[recipient.recipient][i];
            }
        }

        // Add the new recipient
        _userRewardRecipientForToken[recipient.lpTokenId] = recipient;

        // Add the new tokenId to _userTokenIds
        _userTokenIds[recipient.recipient].push(recipient.lpTokenId);
    }

    function onERC721Received(
        address,
        address from,
        uint256 id,
        bytes calldata
    ) external override returns (bytes4) {
        // Only earnkit team EOA can send the NFT here
        if (from != _factory) {
            revert NotAllowed(from);
        }

        emit Received(from, id);
        return IERC721Receiver.onERC721Received.selector;
    }
}
