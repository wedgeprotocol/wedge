# Wedge — Deployment Sequence

Production deploy of the Phase 1 contract set to Base mainnet.

## Prerequisites

- Foundry installed (see root README).
- `BASE_RPC_URL` set in `.env` (Alchemy or similar).
- `PRIVATE_KEY` set in `.env` for the deployer EOA. The deployer becomes
  the `_bootstrap` address on `WedgeRailLocker` (the only address that
  can call `setExtension` once) — this must be the same key for steps 02
  and 03.
- `OWNER` set in `.env` — typically a multisig that becomes the
  `Launchpad`'s owner and is later set as `teamFeeRecipient`. Ownership
  rotation to a Safe is documented in step 06 (TODO; not in this PR).

## Scripts

Each script is invoked via `forge script` against `$BASE_RPC_URL`. They
emit the deployed addresses to stdout — capture them as env vars for the
following step. `--broadcast` actually executes the deploy; without it
the run is a simulation.

```bash
export BASE_RPC_URL=...
export PRIVATE_KEY=...
export OWNER=...
export TEAM_FEE_RECIPIENT=...
```

### 00 — Deploy core (Launchpad + MEV module)

```bash
forge script script/00_DeployCore.s.sol \
  --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Outputs: `Launchpad`, `WedgeMevDescendingFees`.

```bash
export LAUNCHPAD=...
export MEV_MODULE=...
```

### 01 — Mine and deploy the Mainline hook

```bash
forge script script/01_DeployHook.s.sol \
  --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

The script CREATE2-mines a salt such that the hook deploys to an
address with the low 14 bits set to `0xCC` (BEFORE_SWAP + AFTER_SWAP +
their respective RETURNS_DELTA flags). This typically takes a few
seconds.

Outputs: `WedgeMainlineHook` address, salt.

```bash
export MAINLINE_HOOK=...
```

### 02 — Deploy lockers

```bash
forge script script/02_DeployLockers.s.sol \
  --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Outputs: `WedgeLpLocker`, `WedgeRailLocker`.

```bash
export LP_LOCKER=...
export RAIL_LOCKER=...
```

### 03 — Deploy Rail extension + wire locker

```bash
forge script script/03_DeployExtension.s.sol \
  --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Deploys `WedgeRailExtension`, then calls `WedgeRailLocker.setExtension`
from the same deployer EOA (which must be the same key used in step 02).

Outputs: `WedgeRailExtension`.

```bash
export RAIL_EXTENSION=...
```

### 04 — Configure allowlists

```bash
forge script script/04_ConfigureAllowlists.s.sol \
  --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Sets the team-fee recipient, allowlists every Phase 1 contract on the
Launchpad, and lifts the `deprecated` flag. After this step, the
Launchpad can accept `deployToken` calls.

This script must be run as the `Launchpad.owner()` (the address passed
as `OWNER` in step 00).

### 06 — Launch WEDGE + setProtocolToken (operational)

```bash
export TREASURY=...
# Optional overrides:
# export WEDGE_FDV_TICK=230200   # default = ~10 ETH FDV at 100B supply
# export WEDGE_SALT=0x...        # default = keccak256("WEDGE-v1")
forge script script/06_LaunchWedge.s.sol \
  --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Launches WEDGE through the Launchpad using the Classic Mainline preset
(no Rail), then calls `setProtocolToken(WEDGE)` so subsequent launches
can include the Rail extension.

- Must come **after** scripts 00–04 (Launchpad live, allowlists set).
- May run **before or after** step 05. `setProtocolToken` is
  owner-gated; if 05 has rotated ownership to a Safe, run this script
  signed by the Safe.
- **Dev-buy** is intentionally not part of this script — it depends on
  treasury-side parameters that are best chosen at launch time.

Outputs: WEDGE address. The Launchpad's `PROTOCOL_TOKEN()` now
returns it; `setProtocolToken` cannot be called again.

### 05 — Transfer ownership to the Safe multisig

```bash
export SAFE_MULTISIG=...
forge script script/05_TransferOwnership.s.sol \
  --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Rotates `Launchpad.owner()` from the deploy EOA to the configured Safe.
**One-way** (Ownable's single-step transfer). After this, allowlists,
treasury changes, and `setDeprecated` all require multisig signatures.

Run only after confirming the Safe is operational and at least one
signer can produce a valid signature.

### Etherscan verification (per contract)

After all deploy steps, verify each contract on Basescan with
`forge verify-contract`:

```bash
export ETHERSCAN_API_KEY=...

# Launchpad
forge verify-contract $LAUNCHPAD \
  src/Launchpad.sol:Launchpad \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(address)" $OWNER)

# WedgeMevDescendingFees
forge verify-contract $MEV_MODULE \
  src/WedgeMevDescendingFees.sol:WedgeMevDescendingFees \
  --chain base

# WedgeMainlineHook
forge verify-contract $MAINLINE_HOOK \
  src/WedgeMainlineHook.sol:WedgeMainlineHook \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(address,address)" \
    $LAUNCHPAD 0x498581fF718922c3f8e6A244956aF099B2652b2b)

# WedgeLpLocker
forge verify-contract $LP_LOCKER \
  src/WedgeLpLocker.sol:WedgeLpLocker \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(address,address)" \
    $LAUNCHPAD 0x7C5f5A4bBd8fD63184577525326123B519429bDc)

# WedgeRailLocker
forge verify-contract $RAIL_LOCKER \
  src/WedgeRailLocker.sol:WedgeRailLocker \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(address,address)" \
    $LAUNCHPAD 0x7C5f5A4bBd8fD63184577525326123B519429bDc)

# WedgeRailExtension
forge verify-contract $RAIL_EXTENSION \
  src/WedgeRailExtension.sol:WedgeRailExtension \
  --chain base \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address)" \
    $LAUNCHPAD $RAIL_LOCKER \
    0x4200000000000000000000000000000000000006 \
    $MAINLINE_HOOK \
    0x498581fF718922c3f8e6A244956aF099B2652b2b \
    0x7C5f5A4bBd8fD63184577525326123B519429bDc)
```

Confirm each verification on `basescan.org/address/<addr>` shows the
green "Contract" tab before declaring the deploy complete.

## Sequence summary

| Step | Script | Deploys / Configures |
|------|--------|---------------------|
| 00 | `00_DeployCore.s.sol` | Launchpad, WedgeMevDescendingFees |
| 01 | `01_DeployHook.s.sol` | WedgeMainlineHook (CREATE2-mined) |
| 02 | `02_DeployLockers.s.sol` | WedgeLpLocker, WedgeRailLocker |
| 03 | `03_DeployExtension.s.sol` | WedgeRailExtension + setExtension wiring |
| 04 | `04_ConfigureAllowlists.s.sol` | Launchpad allowlists + treasury + un-deprecate |
| 05 | `05_TransferOwnership.s.sol` | Launchpad owner → Safe multisig |
| 06 | `06_LaunchWedge.s.sol` | Launches WEDGE + sets `PROTOCOL_TOKEN` |
| verify | `forge verify-contract` per contract | Basescan source verification |

(05 and 06 are interchangeable in order — both are one-shot. 06 must
be signed by whoever currently holds `Launchpad.owner()`.)

## Post-deploy

After step 04 the Launchpad is functional for Classic Mainline
launches (no Rail). After step 06 the Rail extension also unlocks.
Steps 05 and 06 are independent — once both have run, the deployer
EOA is no longer privileged anywhere in the system.

## Constants

`script/Constants.s.sol` exposes the canonical Base-mainnet addresses
(PoolManager, PositionManager, UniversalRouter, Permit2, WETH).
**Verify each against the upstream source** before broadcasting — they
are pinned at the time of writing but Uniswap may revise.

## What is NOT in this set

- A combined "deploy everything in one tx" script — split into
  steps so each can be re-run independently when an env var is wrong.
- WEDGE dev-buy script — depends on treasury-side parameters (target
  supply %, max slippage, recipient) that are best chosen at launch
  time. Add when those are decided.
