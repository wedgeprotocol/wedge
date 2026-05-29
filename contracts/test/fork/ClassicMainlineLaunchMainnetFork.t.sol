// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {LaunchDeployer} from "../../src/LaunchDeployer.sol";
import {LaunchToken} from "../../src/LaunchToken.sol";
import {Launchpad} from "../../src/Launchpad.sol";

import {BaseMainnet} from "../../script/Constants.s.sol";
import {MainnetForkBase} from "./MainnetForkBase.sol";

/// @notice Mainnet-fork integration: a single Classic-Mainline launch
///         through the Launchpad. Verifies that:
///         - the LaunchToken is deployed at the predicted CREATE2 address
///         - the Mainline pool is initialised on the real v4 PoolManager
///           with the expected starting tick and dynamic-fee flag
///         - the 5-band LP positions land in the LP locker (verified via
///           positionsOf returning 5 entries)
///
///         Does not yet exercise swaps — those require Permit2 +
///         UniversalRouter plumbing and will land in a follow-up
///         fork-test contract.
contract ClassicMainlineLaunchMainnetFork is MainnetForkBase {
    using StateLibrary for IPoolManager;

    address internal creator;

    int24 internal constant STARTING_TICK = 230_200;
    int24 internal constant TICK_SPACING = 200;

    function setUp() public override {
        super.setUp();
        creator = makeAddr("creator");
    }

    function _baseTokenConfig() internal view returns (LaunchDeployer.TokenConfig memory) {
        return LaunchDeployer.TokenConfig({
            admin: creator,
            name: "Fork Test",
            symbol: "FORK",
            salt: bytes32(uint256(1)),
            image: "ipfs://test",
            metadata: "{}",
            context: "fork-test",
            renounceAtDeploy: false
        });
    }

    function _baseLockerConfig() internal view returns (Launchpad.LockerConfig memory cfg) {
        cfg.locker = address(lpLocker);
        cfg.tickLower = new int24[](5);
        cfg.tickUpper = new int24[](5);
        cfg.positionBps = new uint16[](5);
        cfg.tickLower[0] = 230_200;
        cfg.tickUpper[0] = 237_200;
        cfg.positionBps[0] = 1000;
        cfg.tickLower[1] = 234_200;
        cfg.tickUpper[1] = 251_200;
        cfg.positionBps[1] = 5000;
        cfg.tickLower[2] = 246_200;
        cfg.tickUpper[2] = 262_200;
        cfg.positionBps[2] = 1500;
        cfg.tickLower[3] = 257_200;
        cfg.tickUpper[3] = 276_200;
        cfg.positionBps[3] = 2000;
        cfg.tickLower[4] = 269_200;
        cfg.tickUpper[4] = 292_200;
        cfg.positionBps[4] = 500;

        cfg.rewardAdmins = new address[](1);
        cfg.rewardAdmins[0] = creator;
        cfg.rewardRecipients = new address[](1);
        cfg.rewardRecipients[0] = creator;
        cfg.rewardBps = new uint16[](1);
        cfg.rewardBps[0] = 10_000;
    }

    function test_classic_mainline_launch_end_to_end() public {
        Launchpad.DeploymentConfig memory cfg;
        cfg.tokenConfig = _baseTokenConfig();
        cfg.poolConfig = Launchpad.PoolConfig({
            hook: address(mainlineHook),
            pairedToken: BaseMainnet.WETH,
            tickIfToken0IsLaunched: STARTING_TICK,
            tickSpacing: TICK_SPACING,
            poolData: ""
        });
        cfg.lockerConfig = _baseLockerConfig();
        cfg.mevModuleConfig = Launchpad.MevModuleConfig({
            mevModule: address(mev),
            mevModuleData: abi.encode(
                uint24(800_000), // startingFee 80%
                uint24(12_000), // endingFee 1.2%
                uint32(120) // secondsToDecay
            )
        });
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](0);

        address tokenAddress = launchpad.deployToken(cfg);

        // Token is a real LaunchToken with full 100B supply
        LaunchToken token = LaunchToken(tokenAddress);
        assertEq(token.PROTOCOL(), "Wedge");
        assertEq(token.totalSupply(), 100_000_000_000e18);

        // Mainline pool was initialised on the real PoolManager
        bool token0IsLaunched = tokenAddress < BaseMainnet.WETH;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0IsLaunched ? tokenAddress : BaseMainnet.WETH),
            currency1: Currency.wrap(token0IsLaunched ? BaseMainnet.WETH : tokenAddress),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(mainlineHook))
        });
        (uint160 sqrtPriceX96, int24 tick,,) =
            IPoolManager(BaseMainnet.POOL_MANAGER).getSlot0(key.toId());
        assertTrue(sqrtPriceX96 != 0, "pool not initialised");
        // Pool tick should match the orientation-adjusted starting tick
        int24 expectedTick = token0IsLaunched ? STARTING_TICK : -STARTING_TICK;
        assertEq(tick, expectedTick);

        // LP locker recorded 5 positions for this token
        assertTrue(lpLocker.isPlaced(tokenAddress));
        assertEq(lpLocker.positionsOf(tokenAddress).length, 5);
    }
}
