// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LpLocker} from "./LpLocker.sol";
import {EarnkitToken} from "./Earnkit_token.sol";
import {ILocker} from "./Interfaces/ILpLocker.sol";
import {ICampaigns} from "./Interfaces/ICampaign.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager, IUniswapV3Factory, ExactInputSingleParams, ISwapRouter} from "./Interfaces/IEarnkit.sol";

/// @title Earnkit
/// @notice Main contract for deploying and managing Earnkit tokens and liquidity pools
/// @dev Handles token deployment, pool configuration, and reward distribution
contract Earnkit is Ownable {
    using TickMath for int24;

    // Custom errors
    error InvalidSalt();
    error NotOwnerOrAdmin(address caller);
    error NotAllowedPairedToken(address tokenAddress);
    error TokenNotFound(address token);
    error InvalidTick(int24 tick, int24 tickSpacing);

    // Constants
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    // Immutable state variables
    IUniswapV3Factory public immutable uniswapV3Factory;
    INonfungiblePositionManager public immutable positionManager;
    address public immutable swapRouter;

    // Storage variables
    LpLocker public liquidityLocker;
    mapping(address => bool) public admins;
    mapping(address => bool) public allowedPairedTokens;
    address public campaignContract;

    struct PoolConfig {
        address pairedToken;
        uint24 devBuyFee;
        int24 tick;
    }

    struct DeploymentInfo {
        address token;
        uint256 positionId;
        address locker;
    }

    struct CampaignInfo {
        uint256 maxClaims;
        uint256 amountPerClaim;
        uint256 maxSponsoredClaims;
    }

    mapping(address => DeploymentInfo[]) public tokensDeployedByUsers;
    mapping(address => DeploymentInfo) public deploymentInfoForToken;

    event TokenCreated(
        address indexed tokenAddress,
        uint256 indexed positionId,
        address indexed deployer,
        uint256 fid,
        string name,
        string symbol,
        uint256 supply,
        address lockerAddress,
        string castHash
    );

    /// @notice Contract constructor
    /// @param _locker Address of the LP locker contract
    /// @param _uniswapV3Factory Address of UniswapV3 factory
    /// @param _positionManager Address of NFT position manager
    /// @param _swapRouter Address of swap router
    /// @param _owner Address of contract owner
    /// @param _campaignContract Address of campaign contract
    constructor(
        address _locker,
        address _uniswapV3Factory,
        address _positionManager,
        address _swapRouter,
        address _owner,
        address _campaignContract
    ) Ownable(_owner) {
        liquidityLocker = LpLocker(_locker);
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = _swapRouter;
        campaignContract = _campaignContract;
    }

    /// @notice Get all tokens deployed by a specific user
    /// @param _user Address of the user
    /// @return Array of deployment information for user's tokens
    function getTokensDeployedByUser(
        address _user
    ) external view returns (DeploymentInfo[] memory) {
        return tokensDeployedByUsers[_user];
    }

    function configurePool(
        address _newToken,
        address _pairedToken,
        int24 _tick,
        int24 _tickSpacing,
        uint24 _fee,
        uint256 _supplyPerPool,
        address _deployer
    ) internal returns (uint256 positionId) {
        if (_newToken > _pairedToken) revert InvalidSalt();

        uint160 sqrtPriceX96 = _tick.getSqrtRatioAtTick();

        // Create pool
        address pool = uniswapV3Factory.createPool(
            _newToken,
            _pairedToken,
            _fee
        );

        // Initialize pool
        IUniswapV3Factory(pool).initialize(sqrtPriceX96);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams(
                _newToken,
                _pairedToken,
                _fee,
                _tick,
                maxUsableTick(_tickSpacing),
                _supplyPerPool,
                0,
                0,
                0,
                address(this),
                block.timestamp
            );
        (positionId, , , ) = positionManager.mint(params);

        positionManager.safeTransferFrom(
            address(this),
            address(liquidityLocker),
            positionId
        );

        liquidityLocker.addUserRewardRecipient(
            LpLocker.UserRewardRecipient({
                recipient: _deployer,
                lpTokenId: positionId
            })
        );
    }

    function deployToken(
        string calldata _name,
        string calldata _symbol,
        uint256 _supply,
        uint24 _fee,
        bytes32 _salt,
        address _deployer,
        uint256 _fid,
        string memory _image,
        string memory _castHash,
        PoolConfig memory _poolConfig
    ) external payable returns (EarnkitToken token, uint256 positionId) {
        if (!admins[msg.sender] && msg.sender != owner())
            revert NotOwnerOrAdmin(msg.sender);

        if (!allowedPairedTokens[_poolConfig.pairedToken])
            revert NotAllowedPairedToken(_poolConfig.pairedToken);

        int24 tickSpacing = uniswapV3Factory.feeAmountTickSpacing(_fee);
        if (tickSpacing == 0 || _poolConfig.tick % tickSpacing != 0) {
            revert InvalidTick(_poolConfig.tick, tickSpacing);
        }

        token = new EarnkitToken{salt: keccak256(abi.encode(_deployer, _salt))}(
            _name,
            _symbol,
            _supply,
            _deployer,
            _fid,
            _image,
            _castHash
        );

        // Use entire supply for liquidity
        uint256 liquidityAmount = _supply;

        // Approve entire amount for position manager
        token.approve(address(positionManager), liquidityAmount);

        positionId = configurePool(
            address(token),
            _poolConfig.pairedToken,
            _poolConfig.tick,
            tickSpacing,
            _fee,
            liquidityAmount,
            _deployer
        );

        if (msg.value > 0) {
            uint256 amountOut = msg.value;
            // If it's not WETH, we must buy the token first...
            if (_poolConfig.pairedToken != WETH) {
                ExactInputSingleParams
                    memory swapParams = ExactInputSingleParams({
                        tokenIn: WETH, // The token we are exchanging from (ETH wrapped as WETH)
                        tokenOut: _poolConfig.pairedToken, // The token we are exchanging to
                        fee: _poolConfig.devBuyFee, // The pool fee
                        recipient: address(this), // The recipient address
                        amountIn: msg.value, // The amount of ETH (WETH) to be swapped
                        amountOutMinimum: 0, // Minimum amount to receive
                        sqrtPriceLimitX96: 0 // No price limit
                    });

                amountOut = ISwapRouter(swapRouter).exactInputSingle{ // The call to `exactInputSingle` executes the swap.
                    value: msg.value
                }(swapParams);

                IERC20(_poolConfig.pairedToken).approve(
                    address(swapRouter),
                    0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
                );
            }

            ExactInputSingleParams
                memory swapParamsToken = ExactInputSingleParams({
                    tokenIn: _poolConfig.pairedToken, // The token we are exchanging from (ETH wrapped as WETH)
                    tokenOut: address(token), // The token we are exchanging to
                    fee: _fee, // The pool fee
                    recipient: _deployer, // The recipient address
                    amountIn: amountOut, // The amount of ETH (WETH) to be swapped
                    amountOutMinimum: 0, // Minimum amount to receive
                    sqrtPriceLimitX96: 0 // No price limit
                });

            // The call to `exactInputSingle` executes the swap.
            ISwapRouter(swapRouter).exactInputSingle{
                value: _poolConfig.pairedToken == WETH ? msg.value : 0
            }(swapParamsToken);
        }

        DeploymentInfo memory deploymentInfo = DeploymentInfo({
            token: address(token),
            positionId: positionId,
            locker: address(liquidityLocker)
        });

        deploymentInfoForToken[address(token)] = deploymentInfo;
        tokensDeployedByUsers[_deployer].push(deploymentInfo);

        emit TokenCreated(
            address(token),
            positionId,
            _deployer,
            _fid,
            _name,
            _symbol,
            _supply,
            address(liquidityLocker),
            _castHash
        );
    }

    function deployTokenWithCampaigns(
        string calldata _name,
        string calldata _symbol,
        uint256 _supply,
        uint24 _fee,
        bytes32 _salt,
        address _deployer,
        uint256 _fid,
        string memory _image,
        string memory _castHash,
        PoolConfig memory _poolConfig,
        CampaignInfo[] calldata campaigns,
        uint256 campaignPercentage
    ) external payable returns (EarnkitToken token, uint256 positionId) {
        require(
            campaignPercentage <= 100,
            "Campaign percentage must be less than or equal to 100"
        );
        if (!admins[msg.sender] && msg.sender != owner())
            revert NotOwnerOrAdmin(msg.sender);

        if (!allowedPairedTokens[_poolConfig.pairedToken])
            revert NotAllowedPairedToken(_poolConfig.pairedToken);

        int24 tickSpacing = uniswapV3Factory.feeAmountTickSpacing(_fee);
        if (tickSpacing == 0 || _poolConfig.tick % tickSpacing != 0) {
            revert InvalidTick(_poolConfig.tick, tickSpacing);
        }

        token = new EarnkitToken{salt: keccak256(abi.encode(_deployer, _salt))}(
            _name,
            _symbol,
            _supply,
            _deployer,
            _fid,
            _image,
            _castHash
        );

        // Calculate percentage of total supply for campaigns
        uint256 campaignAmount = (_supply * campaignPercentage) / 100;
        uint256 liquidityAmount = _supply - campaignAmount;

        // Approve campaign contract to spend tokens for campaigns
        token.approve(campaignContract, campaignAmount);

        // Create campaigns
        for (uint256 i = 0; i < campaigns.length; i++) {
            CampaignInfo memory campaign = campaigns[i];
            ICampaigns(campaignContract).createCampaign(
                _deployer,
                address(token),
                campaign.maxClaims,
                campaign.amountPerClaim,
                campaign.maxSponsoredClaims
            );
        }

        // Approve remaining 90% for position manager
        token.approve(address(positionManager), liquidityAmount);

        positionId = configurePool(
            address(token),
            _poolConfig.pairedToken,
            _poolConfig.tick,
            tickSpacing,
            _fee,
            liquidityAmount,
            _deployer
        );

        // Handle ETH swaps (same as in deployToken)
        if (msg.value > 0) {
            uint256 amountOut = msg.value;
            if (_poolConfig.pairedToken != WETH) {
                ExactInputSingleParams
                    memory swapParams = ExactInputSingleParams({
                        tokenIn: WETH,
                        tokenOut: _poolConfig.pairedToken,
                        fee: _poolConfig.devBuyFee,
                        recipient: address(this),
                        amountIn: msg.value,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });

                amountOut = ISwapRouter(swapRouter).exactInputSingle{
                    value: msg.value
                }(swapParams);

                IERC20(_poolConfig.pairedToken).approve(
                    address(swapRouter),
                    0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
                );
            }

            ExactInputSingleParams
                memory swapParamsToken = ExactInputSingleParams({
                    tokenIn: _poolConfig.pairedToken,
                    tokenOut: address(token),
                    fee: _fee,
                    recipient: _deployer,
                    amountIn: amountOut,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });

            ISwapRouter(swapRouter).exactInputSingle{
                value: _poolConfig.pairedToken == WETH ? msg.value : 0
            }(swapParamsToken);
        }

        DeploymentInfo memory deploymentInfo = DeploymentInfo({
            token: address(token),
            positionId: positionId,
            locker: address(liquidityLocker)
        });

        deploymentInfoForToken[address(token)] = deploymentInfo;
        tokensDeployedByUsers[_deployer].push(deploymentInfo);

        emit TokenCreated(
            address(token),
            positionId,
            _deployer,
            _fid,
            _name,
            _symbol,
            _supply,
            address(liquidityLocker),
            _castHash
        );
    }

    /// @notice Set or remove admin privileges
    /// @param _admin Address to modify admin status for
    /// @param _isAdmin New admin status
    function setAdmin(address _admin, bool _isAdmin) external onlyOwner {
        admins[_admin] = _isAdmin;
    }

    /// @notice Toggle whether a token can be used as paired token
    /// @param _token Address of token to toggle
    /// @param _allowed New allowed status
    function toggleAllowedPairedToken(
        address _token,
        bool _allowed
    ) external onlyOwner {
        allowedPairedTokens[_token] = _allowed;
    }

    /// @notice Claim rewards for a specific token
    /// @param _token Address of token to claim rewards for
    function claimRewards(address _token) external {
        DeploymentInfo memory deploymentInfo = deploymentInfoForToken[_token];

        if (deploymentInfo.token == address(0)) {
            revert TokenNotFound(_token);
        }

        ILocker(deploymentInfo.locker).collectRewards(
            deploymentInfo.positionId
        );
    }

    /// @notice Update the liquidity locker contract address
    /// @param _newLocker Address of new locker contract
    function updateLiquidityLocker(address _newLocker) external onlyOwner {
        liquidityLocker = LpLocker(_newLocker);
    }

    /// @notice Update the campaign contract address
    /// @param _newCampaignContract Address of new campaign contract
    function updateCampaignContract(
        address _newCampaignContract
    ) external onlyOwner {
        campaignContract = _newCampaignContract;
    }
}

/// @notice Given a tickSpacing, compute the maximum usable tick
/// @param _tickSpacing The spacing between ticks
/// @return Maximum tick that can be used
function maxUsableTick(int24 _tickSpacing) pure returns (int24) {
    unchecked {
        return (TickMath.MAX_TICK / _tickSpacing) * _tickSpacing;
    }
}
