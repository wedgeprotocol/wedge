import Link from "next/link";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";

/**
 * Homepage — locked copy from docs/07.
 *
 * Section order:
 *   1. Hero (product sentence)
 *   2. What a Rail is
 *   3. The three presets
 *   4. Fee model (honest)
 *   5. Scanner stance
 *   6. CTA
 *
 * No gradients. No glass. No hero animation. Single accent only.
 */
export default function Home() {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto w-full max-w-[1180px] px-6">
        <Hero />
        <Divider />
        <WhatARailIs />
        <Divider />
        <ThreePresets />
        <Divider />
        <FeeModel />
        <Divider />
        <ScannerStance />
        <Divider />
        <CTAStrip />
      </main>
      <SiteFooter />
    </>
  );
}

function Divider() {
  return <hr className="my-24 border-t border-[color:var(--color-line)]" aria-hidden />;
}

function Hero() {
  return (
    <section className="pt-24 pb-24">
      <p className="mb-5 text-[0.8125rem] uppercase tracking-[0.18em] text-[color:var(--color-subtle)]">
        Launchpad on Base
      </p>
      <h1 className="max-w-[820px] text-[3rem] leading-[1.05] tracking-tight font-medium sm:text-[3.75rem]">
        Two-pool token launches on Base.
        <br />
        <span className="text-[color:var(--color-muted)]">
          A WETH Mainline and a lower-fee Wedge Rail.
        </span>
      </h1>
      <p className="mt-7 max-w-[640px] text-[1rem] leading-relaxed text-[color:var(--color-muted)]">
        Wedge opens two Uniswap v4 pools per token in one transaction. The fee
        delta between Mainline and Wedge Rail is the wedge — the gap that
        aggregators close by routing through the cheaper pool. Arbitrage flow
        through the Wedge Rail creates structural demand for the WEDGE token
        without taxing creators or removing the WETH pool.
      </p>
      <div className="mt-10 flex flex-wrap items-center gap-3">
        <Link
          href="/launch"
          className="inline-flex h-11 items-center justify-center rounded-[2px] bg-[color:var(--color-accent)] px-5 text-[0.9375rem] font-medium text-[color:var(--color-background)] transition-colors hover:bg-[color:var(--color-accent-press)]"
        >
          Launch a token
        </Link>
        <Link
          href="/docs"
          className="inline-flex h-11 items-center justify-center rounded-[2px] border border-[color:var(--color-line)] px-5 text-[0.9375rem] font-medium text-[color:var(--color-foreground)] transition-colors hover:bg-[color:var(--color-surface)]"
        >
          Read the docs
        </Link>
      </div>
    </section>
  );
}

function WhatARailIs() {
  return (
    <section>
      <SectionLabel>02 · Concept</SectionLabel>
      <SectionTitle>What a Rail is.</SectionTitle>
      <div className="mt-10 grid gap-12 sm:grid-cols-2">
        <p className="text-[1rem] leading-relaxed text-[color:var(--color-muted)]">
          A Rail is a second Uniswap v4 pool, opened in the same transaction as
          the WETH Mainline. The v1 Wedge Rail pairs the new token against the
          WEDGE protocol token at a lower fee — 0.30% vs 1.00% on the Mainline.
        </p>
        <p className="text-[1rem] leading-relaxed text-[color:var(--color-muted)]">
          Aggregators route through whichever pool is cheaper. Most retail
          stays on the Mainline. Large trades and arbitrageurs route through
          the Rail — paying the WEDGE-pool fee on the way through. That flow is
          structural demand for WEDGE, paid by takers, not extracted from
          creators.
        </p>
      </div>
      <RailDiagram className="mt-12" />
    </section>
  );
}

function RailDiagram({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 800 220"
      className={`w-full text-[color:var(--color-muted)] ${className ?? ""}`}
      role="img"
      aria-label="Diagram: Mainline (WETH) on top, Wedge Rail (WEDGE) below, with the wedge driven between them."
    >
      {/* Mainline */}
      <line x1="40" y1="60" x2="760" y2="60" className="stroke" />
      <text x="40" y="40" className="fill-current text-[12px]" style={{ font: "12px Inter" }}>
        Mainline · TOKEN / WETH · 1.00%
      </text>
      {/* Wedge Rail */}
      <line x1="40" y1="160" x2="760" y2="160" className="stroke" />
      <text
        x="40"
        y="190"
        className="fill-current text-[12px]"
        style={{ font: "12px Inter" }}
      >
        Wedge Rail · TOKEN / WEDGE · 0.30%
      </text>
      {/* The wedge — accent color */}
      <path
        d="M 360 160 L 400 60 L 440 160 Z"
        className="stroke"
        style={{ stroke: "var(--accent)" }}
      />
      <text
        x="400"
        y="115"
        textAnchor="middle"
        className="fill-current text-[11px]"
        style={{ font: "11px Inter", fill: "var(--accent)" }}
      >
        Δ70 bps
      </text>
    </svg>
  );
}

function ThreePresets() {
  return (
    <section>
      <SectionLabel>03 · Presets</SectionLabel>
      <SectionTitle>Three presets. One canonical shape.</SectionTitle>
      <div className="mt-12 grid gap-px overflow-hidden rounded-[2px] border border-[color:var(--color-line)] bg-[color:var(--color-line)] sm:grid-cols-3">
        <PresetCard
          name="Classic Mainline"
          line="WETH only. No Rail."
          body="100% of supply across 5 bands on the Mainline. Closest to a Clanker-frontend launch."
        />
        <PresetCard
          name="Balanced Wedge Rail"
          line="80% Mainline · 20% Rail."
          body="Default preset. Mainline opens with 5 bands; Wedge Rail opens with 3. Standard for most launches."
          recommended
        />
        <PresetCard
          name="Heavy Wedge Rail"
          line="Same allocation. Rail-weighted."
          body="Rail bands rebalance toward near-launch depth. For WEDGE-aligned protocol launches."
        />
      </div>
    </section>
  );
}

function PresetCard({
  name,
  line,
  body,
  recommended,
}: {
  name: string;
  line: string;
  body: string;
  recommended?: boolean;
}) {
  return (
    <div className="bg-[color:var(--color-background)] p-7">
      <div className="flex items-center justify-between">
        <h3 className="text-[1rem] font-medium leading-snug">{name}</h3>
        {recommended ? (
          <span className="rounded-[2px] border border-[color:var(--color-accent)] px-1.5 py-0.5 text-[0.6875rem] uppercase tracking-[0.12em] text-[color:var(--color-accent)]">
            Recommended
          </span>
        ) : null}
      </div>
      <p className="mt-2 text-[0.8125rem] uppercase tracking-[0.12em] text-[color:var(--color-subtle)]">
        {line}
      </p>
      <p className="mt-5 text-[0.9375rem] leading-relaxed text-[color:var(--color-muted)]">
        {body}
      </p>
    </div>
  );
}

function FeeModel() {
  return (
    <section>
      <SectionLabel>04 · Fees</SectionLabel>
      <SectionTitle>Honest fee model.</SectionTitle>
      <p className="mt-6 max-w-[680px] text-[1rem] leading-relaxed text-[color:var(--color-muted)]">
        Most launchpads claim &quot;100% LP fees to creators&quot; while their
        hook quietly takes 20% on every swap. Wedge structures the protocol
        take as a separate hook fee, not a skim of the LP fee. Both numbers are
        what they look like.
      </p>
      <div
        className="mt-10 overflow-hidden rounded-[2px] border border-[color:var(--color-line)]"
        data-tnum
      >
        <FeeRow
          pool="Mainline"
          to="Creator"
          rate="1.00%"
          note="Full LP fee on every swap"
        />
        <FeeRow
          pool="Mainline"
          to="Protocol (hook)"
          rate="0.20%"
          note="Separate hook fee, paid by swapper"
        />
        <FeeRow
          pool="Mainline"
          to="Total swap cost"
          rate="1.20%"
          note=""
          emphasised
        />
        <FeeRow
          pool="Wedge Rail"
          to="Protocol treasury"
          rate="0.30%"
          note="Hookless pool; fees fund the protocol"
          emphasised
        />
      </div>
    </section>
  );
}

function FeeRow({
  pool,
  to,
  rate,
  note,
  emphasised,
}: {
  pool: string;
  to: string;
  rate: string;
  note: string;
  emphasised?: boolean;
}) {
  return (
    <div
      className={`grid grid-cols-[120px_1fr_120px] items-center gap-4 border-b border-[color:var(--color-line)] px-5 py-4 last:border-b-0 ${
        emphasised ? "bg-[color:var(--color-surface)]" : ""
      }`}
    >
      <div className="text-[0.75rem] uppercase tracking-[0.14em] text-[color:var(--color-subtle)]">
        {pool}
      </div>
      <div className="text-[0.9375rem]">
        <span className="text-[color:var(--color-foreground)]">{to}</span>
        {note ? (
          <span className="ml-3 text-[color:var(--color-subtle)]">— {note}</span>
        ) : null}
      </div>
      <div className="text-right text-[1.0625rem] tracking-tight">{rate}</div>
    </div>
  );
}

function ScannerStance() {
  return (
    <section>
      <SectionLabel>05 · Scanner-safe</SectionLabel>
      <SectionTitle>Boring token contracts.</SectionTitle>
      <p className="mt-6 max-w-[680px] text-[1rem] leading-relaxed text-[color:var(--color-muted)]">
        LaunchToken is ERC-20 + Permit + Votes + Burnable. No mint, no
        crosschainMint, no pause, no blacklist, no fee setters. The bytecode
        is verified to contain none of the selectors scanners flag.
      </p>
      <p className="mt-4 max-w-[680px] text-[1rem] leading-relaxed text-[color:var(--color-muted)]">
        Supply is fixed at construction. LP positions lock at deploy.
        Admin-gated metadata (image, description) can be updated; or the
        creator can renounce at deploy and freeze the contract entirely.
      </p>
    </section>
  );
}

function CTAStrip() {
  return (
    <section className="pb-32">
      <SectionLabel>06 · Launch</SectionLabel>
      <SectionTitle>Five clicks. Two pools. One transaction.</SectionTitle>
      <div className="mt-8">
        <Link
          href="/launch"
          className="inline-flex h-11 items-center justify-center rounded-[2px] bg-[color:var(--color-accent)] px-5 text-[0.9375rem] font-medium text-[color:var(--color-background)] transition-colors hover:bg-[color:var(--color-accent-press)]"
        >
          Launch a token
        </Link>
      </div>
    </section>
  );
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <p className="text-[0.75rem] uppercase tracking-[0.18em] text-[color:var(--color-subtle)]">
      {children}
    </p>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="mt-4 max-w-[820px] text-[2.25rem] leading-[1.1] tracking-tight font-medium sm:text-[2.625rem]">
      {children}
    </h2>
  );
}
