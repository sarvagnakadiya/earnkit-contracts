// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;
interface ICampaigns {
    function createCampaign(
        address _campaignManager,
        address _tokenAddress,
        uint256 _maxClaims,
        uint256 _amountPerClaim,
        uint256 _maxSponsoredClaims
    ) external payable returns (uint256);
}
