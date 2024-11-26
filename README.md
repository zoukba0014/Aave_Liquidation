# Aave Liquidation Operator

## Installing Foundry

1. Run the following commands to install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Verify installation:
```bash
forge --version
```

## Environment Setup

1. Create `.env` file:
```bash
# Ethereum RPC URL (Infura/Alchemy)
MAINNET_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/YOUR-API-KEY
```

2. Load environment variables:
```bash
source .env
```

## Running Tests

```bash
# Run tests with verbose output
forge test -vv --match-test testLiquidation
```

This will:
- Fork mainnet at block 12489619
- Execute the liquidation
- Display liquidation results