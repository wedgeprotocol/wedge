import Link from "next/link";
import { WedgeMark, WedgeWordmark } from "@/components/wedge-mark";

/**
 * Header — restraint-first. One row, no glass, no shadow.
 * Single bottom hairline as the only visual separator.
 */
export function SiteHeader() {
  return (
    <header className="w-full border-b border-[color:var(--color-line)]">
      <div className="mx-auto flex h-14 max-w-[1180px] items-center justify-between px-6">
        <Link href="/" className="flex items-center gap-2.5 text-[color:var(--color-foreground)]">
          <WedgeMark size={18} />
          <WedgeWordmark />
        </Link>
        <nav className="flex items-center gap-7 text-[0.875rem] text-[color:var(--color-muted)]">
          <Link href="/launch" className="hover:text-[color:var(--color-foreground)]">
            Launch
          </Link>
          <Link href="/pools" className="hover:text-[color:var(--color-foreground)]">
            Pools
          </Link>
          <Link href="/docs" className="hover:text-[color:var(--color-foreground)]">
            Docs
          </Link>
          <Link href="/protocol" className="hover:text-[color:var(--color-foreground)]">
            Protocol
          </Link>
        </nav>
      </div>
    </header>
  );
}
