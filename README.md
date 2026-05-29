# Wedge

**Two-pool token launches on Base.**

Wedge opens two Uniswap v4 pools per token in a single transaction:

- **Mainline** — `TOKEN / WETH`, 1% LP fee. Primary discovery pair.
- **Protocol Rail** — `TOKEN / WEDGE`, 0.30% LP fee. Lower-fee parallel pool.

The fee delta between Mainline and Protocol Rail is the *wedge* — the price gap that aggregators close by routing through the cheaper pool. Arbitrage flow through the Protocol Rail creates structural demand for the `WEDGE` token without taxing creators or removing the WETH pool.

LP positions are locked from deploy. Token contracts are intentionally boring on supply — total supply is fixed at construction, no inflation, no bridge mint, no minting authority of any kind after deploy. Admin-gated `updateImage` / `updateMetadata` / `updateAdmin` are available so creators can correct an image, hand off to a multisig, or update a description after launch. Creators who want maximum scanner trust opt in to `renounceAdmin()` at deploy, which permanently freezes the admin and metadata.

## Status

**Pre-launch.** Contracts in development. No production deployment.

## Build

Requires [Foundry](https://book.getfoundry.sh/).

```bash
git clone --recurse-submodules git@github.com:wedgeprotocol/wedge.git
cd wedge
make build
make test
```

CI runs `forge fmt --check`, `forge build`, and unit tests on every push and pull request. Mainnet-fork integration tests run on a scheduled job with a `BASE_RPC_URL` secret.

## Layout

```
contracts/        Foundry project — Solidity source, tests, deploy scripts
.github/          CI workflows
```

## Audit

**Pending.** Audit will run against the frozen contract set prior to mainnet deployment. No code in this repository has been audited.

## License

MIT — see [`LICENSE`](LICENSE).

## Security

Vulnerability disclosure policy: [`SECURITY.md`](SECURITY.md).

## Links

- Website: [wedgefi.com](https://wedgefi.com)
- X: [@wedgeprotocol](https://x.com/wedgeprotocol)
