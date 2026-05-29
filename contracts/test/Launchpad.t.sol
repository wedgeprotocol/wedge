// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

import {LaunchDeployer} from "../src/LaunchDeployer.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {Launchpad} from "../src/Launchpad.sol";
import {IOwnerAdmins} from "../src/interfaces/IOwnerAdmins.sol";

import {MockExtension} from "./mocks/MockExtension.sol";
import {MockHook} from "./mocks/MockHook.sol";
import {MockLpLocker} from "./mocks/MockLpLocker.sol";
import {MockMevModule} from "./mocks/MockMevModule.sol";

contract LaunchpadTest is Test {
    Launchpad internal launchpad;

    MockHook internal hook;
    MockLpLocker internal locker;
    MockMevModule internal mev;
    MockExtension internal extPlain; // does not require protocol token
    MockExtension internal extNeedsProtocol; // requires protocol token

    address internal owner;
    address internal admin; // launchpad-level admin (allowlist manager)
    address internal creator; // token creator / token admin
    address internal stranger;
    address internal treasury;
    address internal weth;
    address internal wedgeToken; // stand-in for the PROTOCOL token in tests

    function setUp() public {
        owner = makeAddr("owner");
        admin = makeAddr("admin");
        creator = makeAddr("creator");
        stranger = makeAddr("stranger");
        treasury = makeAddr("treasury");
        weth = makeAddr("weth");
        wedgeToken = makeAddr("wedgeToken");

        launchpad = new Launchpad(owner);

        hook = new MockHook();
        locker = new MockLpLocker();
        mev = new MockMevModule();
        extPlain = new MockExtension(false);
        extNeedsProtocol = new MockExtension(true);

        vm.startPrank(owner);
        launchpad.setDeprecated(false);
        launchpad.setAdmin(admin, true);
        launchpad.setHook(address(hook), true);
        launchpad.setLocker(address(locker), address(hook), true);
        launchpad.setMevModule(address(mev), true);
        launchpad.setExtension(address(extPlain), true);
        launchpad.setExtension(address(extNeedsProtocol), true);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────

    function _tokenCfg(bytes32 salt) internal view returns (LaunchDeployer.TokenConfig memory) {
        return LaunchDeployer.TokenConfig({
            admin: creator,
            name: "Test Token",
            symbol: "TEST",
            salt: salt,
            image: "ipfs://x",
            metadata: "{}",
            context: "ctx",
            renounceAtDeploy: false
        });
    }

    function _emptyLockerCfg() internal view returns (Launchpad.LockerConfig memory) {
        return Launchpad.LockerConfig({
            locker: address(locker),
            rewardAdmins: new address[](0),
            rewardRecipients: new address[](0),
            rewardBps: new uint16[](0),
            tickLower: new int24[](0),
            tickUpper: new int24[](0),
            positionBps: new uint16[](0),
            lockerData: ""
        });
    }

    function _baseConfig(bytes32 salt)
        internal
        view
        returns (Launchpad.DeploymentConfig memory cfg)
    {
        cfg.tokenConfig = _tokenCfg(salt);
        cfg.poolConfig = Launchpad.PoolConfig({
            hook: address(hook),
            pairedToken: weth,
            tickIfToken0IsLaunched: int24(230_200),
            tickSpacing: 200,
            poolData: ""
        });
        cfg.lockerConfig = _emptyLockerCfg();
        cfg.mevModuleConfig =
            Launchpad.MevModuleConfig({mevModule: address(mev), mevModuleData: ""});
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](0);
    }

    // ─────────────────────────────────────────────────────────────────
    // Construction & owner controls
    // ─────────────────────────────────────────────────────────────────

    function test_constructor_sets_owner_and_deprecated_true() public {
        Launchpad fresh = new Launchpad(owner);
        assertEq(fresh.owner(), owner);
        assertTrue(fresh.deprecated());
    }

    function test_setDeprecated_owner_only() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        launchpad.setDeprecated(true);

        vm.prank(owner);
        launchpad.setDeprecated(true);
        assertTrue(launchpad.deprecated());
    }

    function test_setTeamFeeRecipient_owner_only_and_emits() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        launchpad.setTeamFeeRecipient(treasury);

        vm.prank(owner);
        launchpad.setTeamFeeRecipient(treasury);
        assertEq(launchpad.teamFeeRecipient(), treasury);
    }

    function test_setProtocolToken_owner_only() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        launchpad.setProtocolToken(wedgeToken);

        vm.prank(owner);
        launchpad.setProtocolToken(wedgeToken);
        assertEq(launchpad.PROTOCOL_TOKEN(), wedgeToken);
    }

    function test_setProtocolToken_second_call_reverts() public {
        vm.startPrank(owner);
        launchpad.setProtocolToken(wedgeToken);
        vm.expectRevert(Launchpad.ProtocolTokenAlreadySet.selector);
        launchpad.setProtocolToken(makeAddr("other"));
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────
    // Allowlist setters
    // ─────────────────────────────────────────────────────────────────

    function test_setHook_admin_can_call() public {
        MockHook newHook = new MockHook();
        vm.prank(admin);
        launchpad.setHook(address(newHook), true);
        assertTrue(launchpad.enabledHooks(address(newHook)));
    }

    function test_setHook_stranger_reverts() public {
        MockHook newHook = new MockHook();
        vm.prank(stranger);
        vm.expectRevert(IOwnerAdmins.Unauthorized.selector);
        launchpad.setHook(address(newHook), true);
    }

    function test_setHook_rejects_wrong_interface() public {
        // weth has no code at all → supportsInterface staticcall fails.
        vm.prank(owner);
        vm.expectRevert();
        launchpad.setHook(weth, true);
    }

    function test_setExtension_rejects_wrong_interface() public {
        vm.prank(owner);
        vm.expectRevert();
        launchpad.setExtension(makeAddr("not-an-extension"), true);
    }

    // ─────────────────────────────────────────────────────────────────
    // deployToken — happy path & guards
    // ─────────────────────────────────────────────────────────────────

    function test_deployToken_reverts_when_deprecated() public {
        vm.prank(owner);
        launchpad.setDeprecated(true);

        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(1)));
        vm.expectRevert(Launchpad.Deprecated.selector);
        launchpad.deployToken(cfg);
    }

    function test_deployToken_happy_path_no_extensions() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(2)));
        address tokenAddr = launchpad.deployToken(cfg);

        LaunchToken token = LaunchToken(tokenAddr);
        assertEq(token.totalSupply(), 100_000_000_000e18);
        assertEq(token.admin(), creator);

        assertTrue(hook.initializePoolCalled());
        assertTrue(hook.initializeMevModuleCalled());
        assertTrue(locker.placeLiquidityCalled());

        Launchpad.DeploymentInfo memory info = launchpad.tokenDeploymentInfo(tokenAddr);
        assertEq(info.token, tokenAddr);
        assertEq(info.hook, address(hook));
        assertEq(info.locker, address(locker));
        assertEq(info.extensions.length, 0);
    }

    function test_deployToken_renounceAtDeploy_true_clears_admin() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(3)));
        cfg.tokenConfig.renounceAtDeploy = true;
        address tokenAddr = launchpad.deployToken(cfg);
        assertEq(LaunchToken(tokenAddr).admin(), address(0));
        // _originalAdmin is preserved as the creator-supplied value.
        assertEq(LaunchToken(tokenAddr).originalAdmin(), creator);
    }

    function test_deployToken_renounceAtDeploy_false_keeps_admin() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(4)));
        cfg.tokenConfig.renounceAtDeploy = false;
        address tokenAddr = launchpad.deployToken(cfg);
        assertEq(LaunchToken(tokenAddr).admin(), creator);
    }

    function test_deployToken_with_plain_extension_no_protocol_needed() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(5)));
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](1);
        cfg.extensionConfigs[0] = Launchpad.ExtensionConfig({
            extension: address(extPlain),
            msgValue: 0,
            extensionBps: 100, // 1% of supply
            extensionData: ""
        });
        launchpad.deployToken(cfg);

        assertTrue(extPlain.receiveTokensCalled());
        assertEq(extPlain.lastSupply(), 100_000_000_000e18 * 100 / 10_000);
    }

    function test_deployToken_extension_needs_protocol_but_unset_reverts() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(6)));
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](1);
        cfg.extensionConfigs[0] = Launchpad.ExtensionConfig({
            extension: address(extNeedsProtocol), msgValue: 0, extensionBps: 100, extensionData: ""
        });
        vm.expectRevert(Launchpad.ProtocolTokenNotSet.selector);
        launchpad.deployToken(cfg);
    }

    function test_deployToken_extension_needs_protocol_succeeds_after_set() public {
        vm.prank(owner);
        launchpad.setProtocolToken(wedgeToken);

        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(7)));
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](1);
        cfg.extensionConfigs[0] = Launchpad.ExtensionConfig({
            extension: address(extNeedsProtocol), msgValue: 0, extensionBps: 100, extensionData: ""
        });
        launchpad.deployToken(cfg);
        assertTrue(extNeedsProtocol.receiveTokensCalled());
    }

    function test_deployToken_unenabled_hook_reverts() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(8)));
        cfg.poolConfig.hook = address(new MockHook()); // not allowlisted
        vm.expectRevert(Launchpad.HookNotEnabled.selector);
        launchpad.deployToken(cfg);
    }

    function test_deployToken_unenabled_locker_reverts() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(9)));
        cfg.lockerConfig.locker = address(new MockLpLocker()); // not allowlisted
        vm.expectRevert(Launchpad.LockerNotEnabled.selector);
        launchpad.deployToken(cfg);
    }

    function test_deployToken_unenabled_extension_reverts() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(10)));
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](1);
        cfg.extensionConfigs[0] = Launchpad.ExtensionConfig({
            extension: address(new MockExtension(false)), // not allowlisted
            msgValue: 0,
            extensionBps: 50,
            extensionData: ""
        });
        vm.expectRevert(Launchpad.ExtensionNotEnabled.selector);
        launchpad.deployToken(cfg);
    }

    function test_deployToken_unenabled_mev_module_reverts() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(11)));
        cfg.mevModuleConfig.mevModule = address(new MockMevModule()); // not allowlisted
        vm.expectRevert(Launchpad.MevModuleNotEnabled.selector);
        launchpad.deployToken(cfg);
    }

    function test_deployToken_extension_msgValue_mismatch_reverts() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(12)));
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](1);
        cfg.extensionConfigs[0] = Launchpad.ExtensionConfig({
            extension: address(extPlain),
            msgValue: 1 ether, // expected
            extensionBps: 100,
            extensionData: ""
        });
        // msg.value = 0 != 1 ether expected
        vm.expectRevert(Launchpad.ExtensionMsgValueMismatch.selector);
        launchpad.deployToken(cfg);
    }

    function test_deployToken_extension_bps_over_max_reverts() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(13)));
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](1);
        cfg.extensionConfigs[0] = Launchpad.ExtensionConfig({
            extension: address(extPlain),
            msgValue: 0,
            extensionBps: 9500, // > MAX_EXTENSION_BPS = 9_000
            extensionData: ""
        });
        vm.expectRevert(Launchpad.MaxExtensionBpsExceeded.selector);
        launchpad.deployToken(cfg);
    }

    function test_deployToken_too_many_extensions_reverts() public {
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(14)));
        cfg.extensionConfigs = new Launchpad.ExtensionConfig[](11); // MAX_EXTENSIONS = 10
        for (uint256 i = 0; i < 11; i++) {
            cfg.extensionConfigs[i] = Launchpad.ExtensionConfig({
                extension: address(extPlain), msgValue: 0, extensionBps: 1, extensionData: ""
            });
        }
        vm.expectRevert(Launchpad.MaxExtensionsExceeded.selector);
        launchpad.deployToken(cfg);
    }

    // ─────────────────────────────────────────────────────────────────
    // Team-fee claim
    // ─────────────────────────────────────────────────────────────────

    function test_claimTeamFees_reverts_when_recipient_unset() public {
        // Deploy a token so launchpad holds some balance briefly; tokens
        // are forwarded to the locker so launchpad balance is zero in
        // the happy path. Doesn't matter — the recipient check fires
        // first.
        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(15)));
        address tokenAddr = launchpad.deployToken(cfg);

        vm.prank(owner);
        vm.expectRevert(Launchpad.TeamFeeRecipientNotSet.selector);
        launchpad.claimTeamFees(tokenAddr);
    }

    function test_claimTeamFees_sweeps_balance_to_recipient() public {
        vm.prank(owner);
        launchpad.setTeamFeeRecipient(treasury);

        Launchpad.DeploymentConfig memory cfg = _baseConfig(bytes32(uint256(16)));
        address tokenAddr = launchpad.deployToken(cfg);

        // Simulate the hook accruing fees to the launchpad over time.
        deal(tokenAddr, address(launchpad), 1000e18);

        vm.prank(owner);
        launchpad.claimTeamFees(tokenAddr);
        assertEq(IERC20(tokenAddr).balanceOf(treasury), 1000e18);
        assertEq(IERC20(tokenAddr).balanceOf(address(launchpad)), 0);
    }
}
