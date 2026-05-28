# Security policy

## Reporting a vulnerability

**Do not file a public GitHub issue for security vulnerabilities.**

To report a vulnerability:

1. Email **security@wedgefi.com** with a description of the issue.
2. Include reproduction steps, affected components, and an estimate of impact.
3. Allow up to 72 hours for an initial response.

We will acknowledge receipt, investigate, and coordinate a disclosure window with you before publishing any fix.

## Scope

Issues in any of the following are in scope:

- Contracts under `contracts/src/` once deployed to Base mainnet.
- The deployment scripts under `contracts/script/`.
- Configuration of allowlisted hooks, lockers, extensions, and MEV modules.

Out of scope:

- Vulnerabilities in upstream dependencies (OpenZeppelin, Uniswap v4-core/periphery, Permit2, Universal Router) — report those upstream.
- Issues in pre-deployment / non-production code.
- Front-running, MEV, and informational issues that do not result in loss of funds for users.

## Pre-launch state

As of the latest commit, no Wedge contracts are deployed to any mainnet. The codebase is in active development and has not yet been audited. The audit will run against the frozen contract set before any mainnet deployment.

## Disclosure timeline

- **T+0**: report received.
- **T+72h**: initial response and triage.
- **T+30d** (typical): coordinated fix deployed, public disclosure within 7 days afterwards.

We will credit reporters who request it.
