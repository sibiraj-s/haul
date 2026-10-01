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
export const PauseIcon = (p: IconProps) => (
  <Glyph {...p}>
    <path d="M9 6v12M15 6v12" />
  </Glyph>
)
export const QueueIcon = (p: IconProps) => (
  <Glyph {...p}>
    <path d="M4 7h16M4 12h16M4 17h10" />
  </Glyph>
)
export const MenuBarIcon = (p: IconProps) => (
  <Glyph {...p}>
    <rect x="3" y="4" width="18" height="16" rx="3" />
    <path d="M3 9h18" />
  </Glyph>
)
export const ScheduleIcon = (p: IconProps) => (
  <Glyph {...p}>
    <circle cx="12" cy="13" r="8" />
    <path d="M12 9v4l2.5 2M9.5 2.5h5" />
  </Glyph>
)
export const BellIcon = (p: IconProps) => (
  <Glyph {...p}>
    <path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0" />
  </Glyph>
)
export const HeartIcon = (p: IconProps) => (
  <Glyph {...p}>
    <path d="M12 20s-7.5-4.6-7.5-10.2A4.1 4.1 0 0 1 12 7.3a4.1 4.1 0 0 1 7.5 2.5C19.5 15.4 12 20 12 20z" />
  </Glyph>
)
