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

## Sequence summary

| Step | Script | Deploys / Configures |
|------|--------|---------------------|
| 00 | `00_DeployCore.s.sol` | Launchpad, WedgeMevDescendingFees |
| 01 | `01_DeployHook.s.sol` | WedgeMainlineHook (CREATE2-mined) |
| 02 | `02_DeployLockers.s.sol` | WedgeLpLocker, WedgeRailLocker |
| 03 | `03_DeployExtension.s.sol` | WedgeRailExtension + setExtension wiring |
| 04 | `04_ConfigureAllowlists.s.sol` | Launchpad allowlists + treasury + un-deprecate |

## Post-deploy

After step 04 the Launchpad is functional for `Classic Mainline`-style
launches (no Rail), but `WedgeRailExtension` will revert until two
further steps:

1. **Launch WEDGE** through the Launchpad with no extension. This
   creates the WEDGE/WETH Mainline pool.
2. **Call `Launchpad.setProtocolToken(WEDGE_ADDRESS)`** — one-shot
   setter, callable only by `Launchpad.owner()`. After this, the Rail
   extension can be included in subsequent launches.

These two steps are operational, not contract-deploy steps. They run
once per protocol lifetime and are documented in the launch runbook
(internal, not in this repo).

## Constants

`script/Constants.s.sol` exposes the canonical Base-mainnet addresses
(PoolManager, PositionManager, UniversalRouter, Permit2, WETH).
**Verify each against the upstream source** before broadcasting — they
are pinned at the time of writing but Uniswap may revise.

## What is NOT in this set

- Ownership transfer to a Safe multisig (deferred to a follow-up).
- Etherscan verification (`forge verify-contract`, deferred).
- A combined "deploy everything in one tx" script — split into
  steps so each can be re-run independently when an env var is wrong.
- WEDGE dev-buy script — operational, written closer to launch day.
