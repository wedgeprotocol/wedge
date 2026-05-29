import { createAppKit } from "@reown/appkit/react";
import { base } from "@reown/appkit/networks";
import { wagmiAdapter, networks } from "@/lib/wagmi";

const projectId = process.env.NEXT_PUBLIC_REOWN_PROJECT_ID ?? "";

// Singleton — the import side-effect in providers.tsx creates the modal.
export const appkit = createAppKit({
  adapters: [wagmiAdapter],
  networks: [...networks],
  defaultNetwork: base,
  projectId,
  metadata: {
    name: "Wedge",
    description:
      "Two-pool token launches on Base. A WETH Mainline and a lower-fee Wedge Rail.",
    url: "https://wedgefi.com",
    icons: ["https://wedgefi.com/icon.png"],
  },
  features: {
    analytics: false,
    email: true,
    socials: ["google", "x", "farcaster"],
    emailShowWallets: true,
  },
  themeMode: "dark",
  themeVariables: {
    "--w3m-accent": "#f5c518",
    "--w3m-color-mix": "#1a1d22",
    "--w3m-color-mix-strength": 20,
    "--w3m-border-radius-master": "2px",
    "--w3m-font-family": "Inter, system-ui, sans-serif",
  },
});
