// Stub for wagmi v3's optional `accounts` connector module.
// We're not using that connector — Reown AppKit covers the wallet UX.
// Turbopack resolves the bare `accounts` import to this empty module so
// the build doesn't fail trying to statically resolve a dynamic import.
export {};
