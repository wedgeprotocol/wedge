# Wedge — top-level commands. All contract work happens under contracts/.

.PHONY: help build test fmt fmt-check snapshot coverage clean install fork

help:
	@echo "Wedge — make targets"
	@echo ""
	@echo "  install     Install Foundry dependencies (git submodules)"
	@echo "  build       Compile contracts"
	@echo "  test        Run unit tests (skips mainnet-fork tests)"
	@echo "  fork        Run mainnet-fork integration tests (needs BASE_RPC_URL)"
	@echo "  fmt         Format Solidity"
	@echo "  fmt-check   Check formatting without modifying"
	@echo "  snapshot    Capture gas snapshot"
	@echo "  coverage    Generate coverage report"
	@echo "  clean       Remove build artifacts"

install:
	git submodule update --init --recursive

build:
	cd contracts && forge build --sizes

test:
	cd contracts && forge test -vvv --no-match-contract MainnetFork

fork:
	@test -n "$$BASE_RPC_URL" || (echo "ERROR: BASE_RPC_URL is required" && exit 1)
	cd contracts && BASE_RPC_URL=$$BASE_RPC_URL forge test --match-contract MainnetFork -vvv

fmt:
	cd contracts && forge fmt src test script

fmt-check:
	cd contracts && forge fmt --check src test script

snapshot:
	cd contracts && forge snapshot

coverage:
	cd contracts && forge coverage --report lcov --report summary

clean:
	cd contracts && forge clean
