import Link from "next/link";

export function SiteFooter() {
  return (
    <footer className="mt-auto border-t border-[color:var(--color-line)]">
      <div className="mx-auto flex max-w-[1180px] flex-col gap-3 px-6 py-8 text-[0.8125rem] text-[color:var(--color-subtle)] sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-3">
          <span>Wedge — two-pool token launches on Base.</span>
        </div>
        <nav className="flex items-center gap-5">
          <Link href="/scanner-status" className="hover:text-[color:var(--color-foreground)]">
            Scanner status
          </Link>
          <Link href="/brand" className="hover:text-[color:var(--color-foreground)]">
            Brand
          </Link>
          <Link
            href="https://github.com/wedgeprotocol/wedge"
            className="hover:text-[color:var(--color-foreground)]"
          >
            GitHub
          </Link>
        </nav>
      </div>
    </footer>
  );
}
