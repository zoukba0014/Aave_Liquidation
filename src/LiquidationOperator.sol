// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ICurvePool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

interface IPriceOracleGetter {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
}

interface ILendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;

    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}

interface IProtocolDataProvider {
    function getReserveTokensAddresses(address asset)
        external
        view
        returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress);
}

interface IDebtToken {
    function balanceOf(address user) external view returns (uint256);
}

contract LiquidationOperator {
    using SafeERC20 for IERC20;

    address constant PRICE_ORACLE = 0xA50ba011c48153De246E5192C8f9258A2ba79Ca9;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address constant TARGET_USER = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant CURVE_POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address constant PROTOCOL_DATA_PROVIDER = 0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d;

    function operate() external {
        // 1. Get the initial state
        (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = ILendingPool(LENDING_POOL).getUserAccountData(TARGET_USER);

        console.log("\n=== Initial State ===");
        console.log("Total Collateral (ETH):", totalCollateralETH);
        console.log("Total Debt (ETH):", totalDebtETH);
        console.log("Liquidation Threshold:", currentLiquidationThreshold);
        console.log("LTV:", ltv);
        console.log("Health Factor:", healthFactor);

        // 2. Get the debt and collateral information
        (,, address variableDebtUSDT) = IProtocolDataProvider(PROTOCOL_DATA_PROVIDER).getReserveTokensAddresses(USDT);
        uint256 userDebtUSDT = IDebtToken(variableDebtUSDT).balanceOf(TARGET_USER);

        (address aWBTCAddress,,) = IProtocolDataProvider(PROTOCOL_DATA_PROVIDER).getReserveTokensAddresses(WBTC);
        uint256 userCollateralWBTC = IERC20(aWBTCAddress).balanceOf(TARGET_USER);

        console.log("\n=== Asset Details ===");
        console.log("WBTC Collateral:", userCollateralWBTC);
        console.log("USDT Debt:", userDebtUSDT);

        // 3. Get the price of WBTC and USDT
        IPriceOracleGetter oracle = IPriceOracleGetter(PRICE_ORACLE);
        uint256 wbtcPrice = oracle.getAssetPrice(WBTC);
        uint256 usdtPrice = oracle.getAssetPrice(USDT);

        console.log("\n=== Oracle Prices ===");
        console.log("WBTC Price:", wbtcPrice);
        console.log("USDT Price:", usdtPrice);

        // 4. Calculate the maximum liquidation amount
        uint256 finalLiquidationAmount =
            calculateLiquidationAmount(userCollateralWBTC, userDebtUSDT, wbtcPrice, usdtPrice);

        address[] memory assets = new address[](1);
        assets[0] = USDC;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = finalLiquidationAmount;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        console.log("\n=== Liquidation Details ===");
        console.log("Debt to cover:", finalLiquidationAmount, "USDT");

        // 5. Flashloan the USDC
        ILendingPool(LENDING_POOL).flashLoan(address(this), assets, amounts, modes, address(this), "", 0);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        console.log("\n=== Starting executeOperation ===");
        uint256 debtToCover = amounts[0];
        uint256 premium = premiums[0];
        uint256 amountToRepay = debtToCover + premium;
        console.log("amountToRepay:", amountToRepay);

        // 1. USDC -> USDT through Curve
        _swapUSDCtoUSDT(debtToCover);
        uint256 usdtReceived = IERC20(USDT).balanceOf(address(this));
        console.log("USDT received from Curve:", usdtReceived);

        // 2. Execute liquidation and handle WBTC
        console.log("\n=== Starting Liquidation ===");
        IERC20(USDT).safeIncreaseAllowance(LENDING_POOL, usdtReceived);

        try ILendingPool(LENDING_POOL).liquidationCall(WBTC, USDT, TARGET_USER, usdtReceived, false) {
            console.log("Liquidation successful");
            uint256 wbtcBalance = IERC20(WBTC).balanceOf(address(this));
            console.log("WBTC received:", wbtcBalance);

            // 3. WBTC -> WETH -> USDC
            uint256 ethReceived = _swapWBTCToETH(wbtcBalance);
            uint256 usdcReceived = _swapETHToUSDC(ethReceived);

            // 4. Handle repayment and remaining USDC
            IERC20(USDC).approve(LENDING_POOL, amountToRepay);
            uint256 remainingUSDC = IERC20(USDC).balanceOf(address(this));
            if (remainingUSDC > amountToRepay) {
                _handleRemainingUSDC(remainingUSDC - amountToRepay);
            }

            // 5. Log the post-liquidation state
            _logPostLiquidationState();
            return true;
        } catch Error(string memory reason) {
            console.log("Liquidation failed:", reason);
            revert(reason);
        }
    }

    function _swapWBTCToETH(uint256 wbtcAmount) internal returns (uint256) {
        IERC20(WBTC).safeIncreaseAllowance(SUSHI_ROUTER, wbtcAmount);
        address[] memory pathToEth = new address[](2);
        pathToEth[0] = WBTC;
        pathToEth[1] = WETH;

        uint256[] memory swapResult = IUniswapV2Router02(SUSHI_ROUTER).swapExactTokensForETH(
            wbtcAmount, 0, pathToEth, address(this), block.timestamp
        );

        console.log("Actual WETH received:", swapResult[1]);
        return swapResult[1];
    }

    function _swapETHToUSDC(uint256 ethAmount) internal returns (uint256) {
        address[] memory pathToUsdc = new address[](2);
        pathToUsdc[0] = WETH;
        pathToUsdc[1] = USDC;

        uint256[] memory swapResult = IUniswapV2Router02(SUSHI_ROUTER).swapExactETHForTokens{value: ethAmount}(
            0, pathToUsdc, address(this), block.timestamp
        );

        console.log("USDC received:", swapResult[1]);
        return swapResult[1];
    }

    function _handleRemainingUSDC(uint256 usdcToSwap) internal {
        console.log("\n=== Converting Remaining USDC to ETH ===");
        console.log("Remaining USDC to swap:", usdcToSwap);

        IERC20(USDC).safeIncreaseAllowance(SUSHI_ROUTER, usdcToSwap);
        address[] memory pathToEth = new address[](2);
        pathToEth[0] = USDC;
        pathToEth[1] = WETH;

        try IUniswapV2Router02(SUSHI_ROUTER).swapExactTokensForETH(
            usdcToSwap, 0, pathToEth, address(this), block.timestamp
        ) returns (uint256[] memory finalSwapResult) {
            console.log("Successfully converted remaining USDC to ETH");
            console.log("ETH received:", finalSwapResult[1]);
        } catch Error(string memory reason) {
            console.log("Failed to convert remaining USDC to ETH:", reason);
        }
    }

    function calculateLiquidationAmount(
        uint256 totalCollateralWBTC,
        uint256 totalDebtUSDT,
        uint256 wbtcPrice,
        uint256 usdtPrice
    ) internal pure returns (uint256) {
        uint256 wbtcValue = totalCollateralWBTC * wbtcPrice;
        uint256 adjustedValue = wbtcValue * 10 / 11;

        uint256 amountUSDT = adjustedValue * 1e6 / 1e8 / usdtPrice;
        console.log("amountUSDT:", amountUSDT);
        console.log("totalDebtUSDT:", totalDebtUSDT);

        if (amountUSDT > (totalDebtUSDT * 5000 / 10000)) {
            console.log("amountUSDT > (totalDebtUSDT * 5000 / 10000)");
            amountUSDT = totalDebtUSDT * 5000 / 10000;
        }

        return amountUSDT;
    }

    function _swapUSDCtoUSDT(uint256 amount) internal {
        uint256 oldAllowance = IERC20(USDC).allowance(address(this), CURVE_POOL);
        if (oldAllowance > 0) {
            IERC20(USDC).approve(CURVE_POOL, 0);
        }
        IERC20(USDC).approve(CURVE_POOL, amount);
        console.log("USDC approved for Curve:", amount);

        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(address(this));

        ICurvePool(CURVE_POOL).exchange(1, 2, amount, 0);
    }

    function _logPostLiquidationState() internal view {
        console.log("\n=== Post-Liquidation State ===");
        (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = ILendingPool(LENDING_POOL).getUserAccountData(TARGET_USER);

        console.log("Total Collateral (ETH):", totalCollateralETH);
        console.log("Total Debt (ETH):", totalDebtETH);
        console.log("Liquidation Threshold:", currentLiquidationThreshold);
        console.log("LTV:", ltv);
        console.log("Health Factor:", healthFactor);
    }

    receive() external payable {}
}
