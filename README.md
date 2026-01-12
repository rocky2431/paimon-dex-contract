# Paimon DEX

V2-style AMM DEX contracts for the Paimon Finance ecosystem on BSC.

## Overview

Paimon DEX implements a constant product (x·y=k) automated market maker, similar to Uniswap V2 but upgraded to Solidity 0.8.24 with modern features.

## Features

- **PaimonFactory**: CREATE2-based pair deployment
- **PaimonPair**: AMM core with flash swap support
- **PaimonRouter**: Multi-hop swaps and liquidity management
- **EIP-2612**: Gasless approvals via permit

## Technical Stack

- Solidity: ^0.8.24
- Framework: Foundry
- Target: BSC (BNB Smart Chain)
- EVM Version: Paris

## Project Structure

```
src/
├── core/
│   ├── PaimonERC20.sol      # LP Token with permit
│   ├── PaimonFactory.sol    # Pair factory
│   ├── PaimonPair.sol       # AMM pair
│   └── libraries/
│       ├── Math.sol
│       └── UQ112x112.sol
├── periphery/
│   ├── PaimonRouter.sol     # Trade router
│   └── libraries/
│       └── PaimonLibrary.sol
└── interfaces/
```

## Development

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Test with verbosity

```bash
forge test -vvv
```

## License

MIT
