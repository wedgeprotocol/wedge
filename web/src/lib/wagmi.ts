import { WagmiAdapter } from "@reown/appkit-adapter-wagmi";
import { base } from "@reown/appkit/networks";

const projectId = process.env.NEXT_PUBLIC_REOWN_PROJECT_ID ?? "";

if (!projectId && typeof window !== "undefined") {
  // Surfacing as a console warning in dev — production builds should fail
  // explicitly when the env var is missing, but we don't want to crash
  // local development for visual work.
  console.warn(
    "NEXT_PUBLIC_REOWN_PROJECT_ID is not set. Get one at https://cloud.reown.com and add it to .env.local."
  );
}

export const networks = [base] as const;

export const wagmiAdapter = new WagmiAdapter({
  networks: [...networks],
  projectId,
  ssr: true,
});

export const wagmiConfig = wagmiAdapter.wagmiConfig;
