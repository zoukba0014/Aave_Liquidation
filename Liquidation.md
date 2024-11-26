# Aave Liquidation Operator
## Summary
This is a liquidation operator for Aave. For this specific operator, target user is 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F. The target user stake 94 WTC to loan 10903029 USDT. Though the test i had done, we can liquidation all most of the collateral and the best profit is 83ETH.

## Analysis
### Aave liquidation
1. health factor
$$
\text{Health Factor} = \frac{\text{Total Collateral Value} \times \text{Weighted Average Liquidation Threshold}}{\text{Total Borrow Value}}
$$
health factor is the symbol that represent the status of the user's position. If health factor is less than 1, the user's position is liquidatable.

2. liquidation bonus
$$
\text{Discounted Collateral Value} = \text{Collateral Value} \times (1 + \text{Liquidation Bonus Rate})
$$
the liquidation bonus represent the discount when you buy the collateral. for example, for this current test, the liquidation bonus is 10%, which means when we liquidate the collateral, we will get 10% discount.

3. Maximum liquidation amount(The best profit)

The Maximum asset value we can liquidate is the Collateral Value, because the liquidation exsist, 所以我们只要花费:
$$
\text{Maximum Spend} = \frac{\text{Collateral Value}}{1 + \text{Liquidation Bonus}}
$$
But Aave has a rule that limits repayment to no more than 50% of the borrowed amount. So, to figure out the maximum profit, we just take the smaller value between these two. That gives us the best profit we can get.
$$
\text{Maximum Liquidation Amount} = \min\left(\frac{\text{Collateral Value}}{1 + \text{Liquidation Bonus}}, 0.5 \times \text{Total Borrow Value}\right)
$$

###  Choose the best path in DEX
1. Slippage:

    a. When swapping USDC to USDT, different DEXes have varying slippage rates. Slippage significantly impacts your final profit. For example, when swapping on Uniswap, the slippage might be 0.5%, which is too high for large stablecoin transactions, especially when using flashloans to borrow a substantial amount of coins.

    b. For large swaps, you can consider splitting the swap amount across multiple DEXes to minimize slippage or use multi-path strategies to further optimize the transaction.

## Reason
I think the reason for this liquidation is the price fluctuation of BTC or the de-pegging of WBTC. This is based on my observation data.
```bash
=== Initial State ===
  Total Collateral (ETH): 10630629178806013179408
  Total Debt (ETH): 8093660042623032904515
  Liquidation Threshold: 7561
  LTV: 7082
  Health Factor: 993100609584077736

=== Asset Details ===
  WBTC Collateral: 9427338222
  USDT Debt: 10903029217172
  
=== Oracle Prices ===
  WBTC Price: 16638242604905507000
  USDT Price: 488945000000000
```
It can be seen that BTC has significantly depreciated against ETH.

PS: USDT is not ERC20 token! USDT is not ERC20 token! USDT is not ERC20 token!



