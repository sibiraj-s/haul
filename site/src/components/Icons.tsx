import type { SVGProps } from 'react'

/// Line glyphs on a 24pt grid; size and stroke colour come from the caller's classes.
function Glyph({ children, className = '', ...props }: SVGProps<SVGSVGElement>) {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      className={`fill-none stroke-current [stroke-linecap:round] [stroke-linejoin:round] ${className}`}
      {...props}
    >
      {children}
    </svg>
  )
}

type IconProps = { className?: string }

export const DownloadIcon = (p: IconProps) => (
  <Glyph {...p}>
    <path d="M12 4v10.5M7.3 10L12 14.7 16.7 10M5 19h14" />
  </Glyph>
)
export const ConnectionsIcon = (p: IconProps) => (
  <Glyph {...p}>
    <path d="M4 7h11M4 12h16M4 17h13M16 4l3 3-3 3" />
  </Glyph>
)
export const QueueIcon = (p: IconProps) => (
  <Glyph {...p}>
    <path d="M4 7h16M4 12h16M4 17h10" />
  </Glyph>
)
export const ScheduleIcon = (p: IconProps) => (
  <Glyph {...p}>
    <circle cx="12" cy="13" r="8" />
    <path d="M12 9v4l2.5 2M9.5 2.5h5" />
  </Glyph>
)
export const BrowserIcon = (p: IconProps) => (
  <Glyph {...p}>
    <rect x="3" y="4.5" width="18" height="15" rx="2.5" />
    <path d="M3 9h18M12 11.5v5M9.5 14l2.5 2.5 2.5-2.5" />
  </Glyph>
)
export const RemoteIcon = (p: IconProps) => (
  <Glyph {...p}>
    <rect x="4" y="3" width="9" height="18" rx="2" />
    <path d="M8 17.5h1M16.5 9a4 4 0 0 1 0 6M19 6.5a8 8 0 0 1 0 11" />
  </Glyph>
)
export const LockIcon = (p: IconProps) => (
  <Glyph {...p}>
    <rect x="5" y="10.5" width="14" height="10" rx="2" />
    <path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" />
  </Glyph>
)
export const HeartIcon = (p: IconProps) => (
  <Glyph {...p}>
    <path d="M12 20s-7.5-4.6-7.5-10.2A4.1 4.1 0 0 1 12 7.3a4.1 4.1 0 0 1 7.5 2.5C19.5 15.4 12 20 12 20z" />
  </Glyph>
)
