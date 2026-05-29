import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // wagmi v3 lazily imports an optional `accounts` connector that we
  // don't use (Reown AppKit covers the wallet UX). Turbopack can't tell
  // the import is dynamic + caught, so we alias it to an empty stub.
  turbopack: {
    resolveAlias: {
      accounts: "./src/lib/stubs/empty-module.ts",
    },
  },
  webpack: (config) => {
    config.resolve = config.resolve ?? {};
    config.resolve.alias = {
      ...(config.resolve.alias ?? {}),
      accounts: path.resolve(__dirname, "src/lib/stubs/empty-module.ts"),
    };
    return config;
  },
};

export default nextConfig;
