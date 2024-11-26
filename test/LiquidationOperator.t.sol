// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/LiquidationOperator.sol";

contract LiquidationOperatorTest is Test {
    LiquidationOperator public liquidator;

    function setUp() public {
        // Fork mainnet at block 12489619 (清算前的区块)
        vm.createSelectFork(vm.rpcUrl("mainnet"), 12489619);

        // Deploy liquidator
        liquidator = new LiquidationOperator();
        vm.deal(address(liquidator), 2 ether);
    }

    function testLiquidation() public {
        uint256 initialBalance = address(liquidator).balance;
        liquidator.operate();

        uint256 finalBalance = address(liquidator).balance;
        console.log("Final Balance:", finalBalance / 1e18);
        uint256 profit = finalBalance - initialBalance;

        console.log("\n=== Post-Liquidation ===");
        console.log("Profit (ETH):", profit / 1e18);

        assertGe(profit, 43 ether, "Insufficient profit");
    }
}
