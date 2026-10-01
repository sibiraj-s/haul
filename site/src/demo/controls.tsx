import type { ButtonHTMLAttributes, CSSProperties, ReactNode } from 'react'
import { extOf, KINDS, type Kind } from './model'

/// Stroke paths on a 24pt grid, standing in for the app's SF Symbols.
export const ICON = {
  all: 'M4 13l2.5-7h11L20 13v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1zM4 13h4.5l1 2h5l1-2H20',
  active: 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18zM12 7.5v8M8.5 12.5L12 16l3.5-3.5',
  queued: 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18zM12 7v5l3 2',
  completed: 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18zM8 12.5l2.7 2.7L16 9.8',
  failed: 'M12 4L2.8 19.5h18.4zM12 10v4.5M12 17.2v.1',
  video: 'M4 5h16v14H4zM8 5v14M16 5v14M4 9h4M4 15h4M16 9h4M16 15h4',
  audio: 'M9 18V6l10-2v12M9 18a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0zM19 16a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0z',
  image: 'M4 5h16v14H4zM4 16l5-5 4 4 3-3 4 4M15.5 8.5v.1',
  doc: 'M7 3h7l4 4v14H7zM14 3v4h4M9.5 12h6M9.5 15.5h6',
  archive: 'M4 5h16v4H4zM5 9v10h14V9M10 13h4',
  app: 'M12 3l8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9',
  pause: 'M9 6v12M15 6v12',
  play: 'M8 5.5v13l10-6.5z',
  retry: 'M4.5 12a7.5 7.5 0 1 0 2.2-5.3M4.5 4.5v4h4',
  gear: 'M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6zM12 2.5v3M12 18.5v3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M2.5 12h3M18.5 12h3M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1',
  download: 'M12 4v11M7.5 10.5L12 15l4.5-4.5M5 19.5h14',
  globe: 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18zM3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18',
  bell: 'M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0',
  info: 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18zM12 11v5.5M12 7.6v.4',
  sidebarLeft: 'M4 5.5h16v13H4zM9.5 5.5v13',
  sidebarRight: 'M4 5.5h16v13H4zM14.5 5.5v13',
  gauge: 'M4 16.5a8 8 0 1 1 16 0M12 16.5l3.8-4.6',
  plus: 'M12 5v14M5 12h14',
  search: 'M10.5 4a6.5 6.5 0 1 0 0 13a6.5 6.5 0 1 0 0-13zM15.5 15.5L20 20',
  folder: 'M3 7a1 1 0 0 1 1-1h5l2 2h9a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z',
  chevrons: 'M8 10l4-4 4 4M8 14l4 4 4-4',
  up: 'M6 15l6-6 6 6',
  down: 'M6 9l6 6 6-6',
  check: 'M6 12.5l4 4 8-9',
  close: 'M7 7l10 10M17 7L7 17',
  pencil: 'M4 20h4L19 9l-4-4L4 16zM13.5 6.5l4 4',
  warning: 'M12 4L2.8 19.5h18.4zM12 10v4.5M12 17.2v.1',
  heart: 'M12 20s-7.5-4.6-7.5-10.2A4.1 4.1 0 0 1 12 7.3a4.1 4.1 0 0 1 7.5 2.5C19.5 15.4 12 20 12 20z',
  haul: 'M12 4v10.5M7.3 10L12 14.7 16.7 10M5 19h14',
}

export const cx = (...classes: (string | false | null | undefined)[]) => classes.filter(Boolean).join(' ')

export function Glyph({
  d,
  size = 16,
  width = 1.8,
  className,
  style,
}: {
  d: string
  size?: number
  width?: number
  className?: string
  style?: CSSProperties
}) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={cx('flex-none fill-none stroke-current', className)}
      style={{
        width: size,
        height: size,
        strokeWidth: width,
        strokeLinecap: 'round',
        strokeLinejoin: 'round',
        ...style,
      }}
      aria-hidden="true"
    >
      <path d={d} />
    </svg>
  )
}

export function FileIcon({
  name,
  kind,
  width,
  height,
  band,
  fontSize,
  radius,
}: {
  name?: string
  kind: Kind
  width: number
  height: number
  band: number
  fontSize?: number
  radius: number
}) {
  return (
    <div
      className="relative flex-none overflow-hidden bg-page shadow-[0_0_0_.5px_var(--ctlB),0_1px_2px_rgba(0,0,0,.12)]"
      style={{ width, height, borderRadius: radius }}
    >
      <div
        className="absolute inset-x-0 bottom-0 flex items-center justify-center font-extrabold tracking-[.02em] text-white"
        style={{ height: band, background: KINDS[kind].color, fontSize }}
      >
        {name && extOf(name).toUpperCase().slice(0, 4)}
      </div>
    </div>
  )
}

export function AppTile({ size, radius, glyph }: { size: number; radius: number; glyph: number }) {
  return (
    <div
      className="flex flex-none items-center justify-center bg-accent text-white shadow-icon"
      style={{ width: size, height: size, borderRadius: radius }}
    >
      <Glyph d={ICON.haul} size={glyph} width={2.2} />
    </div>
  )
}

/// Capsule-shaped button in the app's control style; `prominent` fills it with the accent.
export function Pill({
  prominent,
  small,
  className,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { prominent?: boolean; small?: boolean }) {
  return (
    <button
      {...props}
      className={cx(
        'inline-flex items-center justify-center whitespace-nowrap disabled:opacity-45',
        small ? 'h-6.5 rounded-[13px] px-3 text-xs' : 'h-7 rounded-[14px] px-4',
        prominent ? 'bg-accent font-medium text-white' : 'bg-ctl shadow-ctl',
        className,
      )}
    />
  )
}

export function Switch({ on, onChange }: { on: boolean; onChange: (on: boolean) => void }) {
  return (
    <button
      role="switch"
      aria-checked={on}
      onClick={() => onChange(!on)}
      className={cx(
        'relative h-4.5 w-8 flex-none rounded-[9px] transition-colors duration-150',
        on ? 'bg-accent' : 'bg-track',
      )}
    >
      <span
        className={cx(
          'absolute top-px size-4 rounded-full bg-white shadow-[0_1px_2px_rgba(0,0,0,.3)] transition-[left] duration-150',
          on ? 'left-3.75' : 'left-px',
        )}
      />
    </button>
  )
}

export function Segmented<T extends string | number | boolean>({
  options,
  value,
  onChange,
  minWidth,
}: {
  options: [T, string][]
  value: T
  onChange: (v: T) => void
  minWidth?: number
}) {
  return (
    <div className="flex gap-0.5 rounded-[7px] bg-field p-0.5">
      {options.map(([v, label]) => (
        <button
          key={String(v)}
          onClick={() => onChange(v)}
          style={{ minWidth }}
          className={cx('h-5.5 rounded-[5px] px-2 text-center text-xs', v === value && 'bg-ctl shadow-ctl')}
        >
          {label}
        </button>
      ))}
    </div>
  )
}

/// A pop-up button: shows the current choice and opens a native menu.
export function PopUp<T extends string | number>({
  options,
  value,
  onChange,
  icon,
}: {
  options: [T, string][]
  value: T
  onChange: (v: T) => void
  icon?: ReactNode
}) {
  return (
    <label className="relative inline-flex h-6 items-center gap-1.5 whitespace-nowrap rounded-md bg-ctl px-2 shadow-ctl">
      {icon}
      <span>{options.find(([v]) => v === value)?.[1]}</span>
      <Glyph d={ICON.chevrons} size={10} width={2.4} className="opacity-60" />
      <select
        className="absolute inset-0 w-full appearance-none opacity-0"
        value={String(value)}
        onChange={(e) => {
          const picked = options.find(([v]) => String(v) === e.target.value)
          if (picked) onChange(picked[0])
        }}
      >
        {options.map(([v, label]) => (
          <option key={String(v)} value={String(v)}>
            {label}
          </option>
        ))}
      </select>
    </label>
  )
}

export function Checkbox({
  on,
  onChange,
  children,
}: {
  on: boolean
  onChange: (on: boolean) => void
  children: ReactNode
}) {
  return (
    <button className="flex items-center gap-1.75" onClick={() => onChange(!on)}>
      <span
        className={cx(
          'flex size-3.5 items-center justify-center rounded',
          on ? 'bg-accent text-white' : 'bg-ctl shadow-[inset_0_0_0_1px_var(--ctlB)]',
        )}
      >
        {on && <Glyph d={ICON.check} size={11} width={3.2} />}
      </span>
      {children}
    </button>
  )
}

/// Rounded group of rows with hairlines between them, like the app's DesignGroup.
export function Group({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cx('flex flex-col rounded-[10px] bg-group [&>*+*]:border-t-[.5px] [&>*+*]:border-sep', className)}>
      {children}
    </div>
  )
}

/// A settings row: title and optional caption on the left, a control on the right.
export function Row({ title, caption, children }: { title: ReactNode; caption?: string; children?: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 px-3 py-2.5">
      <div>
        <div>{title}</div>
        {caption && <div className="mt-0.5 text-[11px] text-text2">{caption}</div>}
      </div>
      {children}
    </div>
  )
}

export function Bar({
  value,
  fill,
  height,
  track = 'var(--track)',
}: {
  value: number
  fill: string
  height: number
  track?: string
}) {
  return (
    <div className="overflow-hidden rounded-sm" style={{ height, background: track }}>
      <div
        className="h-full rounded-sm transition-[width] duration-500 ease-linear"
        style={{ width: `${(value * 100).toFixed(2)}%`, background: fill }}
      />
    </div>
  )
}
