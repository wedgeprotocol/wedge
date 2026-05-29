/**
 * Wedge logomark — a single geometric wedge driven between two horizontal
 * rules. The two rules are Mainline and Wedge Rail; the wedge is the fee
 * delta between them. Single-line stroke graphic per docs/07.
 *
 * `size` controls overall height in px. Stroke is rendered with
 * `vector-effect: non-scaling-stroke` (from .stroke util) so the mark
 * stays optically consistent at any size.
 */
export function WedgeMark({
  size = 24,
  className,
}: {
  size?: number;
  className?: string;
}) {
  return (
    <svg
      width={(size * 32) / 18}
      height={size}
      viewBox="0 0 32 18"
      role="img"
      aria-label="Wedge"
      className={className}
    >
      {/* Top rail (Mainline) */}
      <line x1="1" y1="3" x2="31" y2="3" className="stroke" />
      {/* Bottom rail (Wedge Rail) */}
      <line x1="1" y1="15" x2="31" y2="15" className="stroke" />
      {/* Wedge — narrow triangle driven between the rails */}
      <path
        d="M 8 15 L 16 3 L 24 15 Z"
        className="stroke"
        style={{ stroke: "var(--accent)" }}
      />
    </svg>
  );
}

export function WedgeWordmark({ className }: { className?: string }) {
  return (
    <span
      className={`font-sans font-medium tracking-tight text-[1.125rem] leading-none ${className ?? ""}`}
    >
      wedge
    </span>
  );
}
