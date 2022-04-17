# sol-tuts

Contains contracts and tests for [solidity mentorship](https://github.com/alcueca/solidity-mentorship) problems by [@alcueca](https://github.com/alcueca).

## Contracts

- [Registry](src/Registry.sol)
- [Vault1](src/Vault1.sol)
- [Vault2](src/Vault2.sol)
- [Vault3](src/Vault3.sol)
- [CollateralizedVault](src/CollateralizedVault.sol)
- [MultiCollateralVault](src/MultiCollateralVault.sol): With `AccessControl`.
- [xy = k AMM](https://github.com/dsam82/unifap-v2)

## Disclaimer

This is **experimental software** and is provided on an "as is" and "as available" basis.

This repository contains unaudited code, written only for learning purposes. Please check thorougly for use in **production**.

## Setup

Run `forge test` to run tests.

Check [SETUP.md](SETUP.md) for configurations.

## Acknowledgements

These contracts were inspired by or directly modified from many sources, primarily:

- [Solmate](https://github.com/rari-capital/Solmate)
- [yield-utils-v2](https://github.com/yield/yield-utils-v2)

> Note: This repo uses [Foundry](https://github.com/foundry-rs/foundry) for tests.