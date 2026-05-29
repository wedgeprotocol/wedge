// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Shared address constants used by the Wedge deploy scripts.
///         Verify each address against the canonical source before
///         broadcasting to mainnet.
library BaseMainnet {
    // Uniswap v4 — Base mainnet
    // Source: https://docs.uniswap.org/contracts/v4/deployments
    address internal constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address internal constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;

    // Permit2 — canonical deterministic deploy
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // WETH9 on Base
    address internal constant WETH = 0x4200000000000000000000000000000000000006;

    // Foundry default CREATE2 Deployer Proxy (used by `vm.startBroadcast`
    // when deploying with a `{salt: ...}` literal).
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
}
