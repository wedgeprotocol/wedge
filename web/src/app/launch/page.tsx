"use client";

import Link from "next/link";
import { useAccount, useDisconnect } from "wagmi";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";

const STEPS = [
  "Connect",
  "Token basics",
  "Preset",
  "Fee preview",
  "Scanner check",
  "Deploy",
] as const;

const CURRENT_STEP = 0;

export default function LaunchPage() {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto w-full max-w-[820px] px-6 py-16">
        <StepBar />
        <h1 className="mt-12 text-[2rem] leading-tight tracking-tight font-medium">
          Connect a wallet.
        </h1>
        <p className="mt-3 max-w-[560px] text-[0.9375rem] leading-relaxed text-[color:var(--color-muted)]">
          Wedge launches need a Base-mainnet wallet. Sign in with email or
          social if you don&apos;t have one yet — a wallet will be created for
          you and you can move it on-chain later.
        </p>
        <ConnectStep />
      </main>
      <SiteFooter />
    </>
  );
}

function StepBar() {
  return (
    <ol className="flex w-full items-center gap-2 text-[0.75rem] uppercase tracking-[0.14em]">
      {STEPS.map((label, i) => {
        const done = i < CURRENT_STEP;
        const current = i === CURRENT_STEP;
        return (
          <li
            key={label}
            className="flex flex-1 items-center gap-2 text-[color:var(--color-subtle)]"
            aria-current={current ? "step" : undefined}
          >
            <span
              className={`flex h-5 w-5 items-center justify-center rounded-[2px] border text-[0.6875rem] tabular-nums ${
                current
                  ? "border-[color:var(--color-accent)] text-[color:var(--color-accent)]"
                  : done
                    ? "border-[color:var(--color-muted)] text-[color:var(--color-muted)]"
                    : "border-[color:var(--color-line)]"
              }`}
            >
              {i + 1}
            </span>
            <span
              className={`hidden sm:inline ${
                current
                  ? "text-[color:var(--color-foreground)]"
                  : done
                    ? "text-[color:var(--color-muted)]"
                    : ""
              }`}
            >
              {label}
            </span>
          </li>
        );
      })}
    </ol>
  );
}

function ConnectStep() {
  const { isConnected, address } = useAccount();
  const { disconnect } = useDisconnect();

  if (isConnected && address) {
    return (
      <div className="mt-10 rounded-[2px] border border-[color:var(--color-line)] bg-[color:var(--color-surface)] p-6">
        <p className="text-[0.75rem] uppercase tracking-[0.14em] text-[color:var(--color-subtle)]">
          Connected
        </p>
        <p
          className="mt-2 font-mono text-[0.9375rem] text-[color:var(--color-foreground)]"
          data-tnum
        >
          {address.slice(0, 6)}…{address.slice(-4)}
        </p>
        <div className="mt-6 flex items-center gap-3">
          <Link
            href="/launch/basics"
            className="inline-flex h-10 items-center justify-center rounded-[2px] bg-[color:var(--color-accent)] px-4 text-[0.9375rem] font-medium text-[color:var(--color-background)] hover:bg-[color:var(--color-accent-press)]"
          >
            Continue
          </Link>
          <button
            type="button"
            onClick={() => disconnect()}
            className="text-[0.875rem] text-[color:var(--color-subtle)] hover:text-[color:var(--color-foreground)]"
          >
            Disconnect
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="mt-10">
      {/* `appkit-button` is the Reown AppKit web component, registered when
          `src/lib/appkit.ts` runs. It handles its own theming via the
          themeVariables we set there. */}
      <appkit-button balance="hide" />
    </div>
  );
}
