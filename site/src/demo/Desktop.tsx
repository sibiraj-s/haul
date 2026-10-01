import { AppTile, Bar, cx, FileIcon, Glyph, ICON, Pill } from './controls'
import { subtitle } from './MainWindow'
import { fmtBytes, folderFor, statusLine } from './model'
import { isUnfinished, progress, type Demo } from './useDemo'

const RING = 2 * Math.PI * 8

/// Overall progress of everything downloading, by bytes.
function overall(demo: Demo) {
  const running = demo.state.items.filter((d) => d.status === 'downloading')
  const total = running.reduce((a, d) => a + d.size, 0)
  return total ? running.reduce((a, d) => a + d.size * progress(d), 0) / total : 0
}

export function MenuBar({ demo }: { demo: Demo }) {
  const { state, update } = demo
  const running = state.items.filter((d) => d.status === 'downloading')
  const speed = running.reduce((a, d) => a + d.speed, 0)
  const now = new Date()
  const clock =
    now.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }).replace(',', '') +
    '  ' +
    now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
  const toggleMenu = (menu: 'app' | 'extra') => update((s) => ({ menu: s.menu === menu ? null : menu }))

  return (
    <div className="absolute inset-x-0 top-0 z-45 flex h-7 items-center gap-4.5 px-3.5">
      <button
        onClick={() => toggleMenu('app')}
        className={cx('rounded-[5px] px-1.5 py-0.5 font-bold', state.menu === 'app' && 'glass')}
      >
        Haul
      </button>
      <div className="flex gap-4">
        {['File', 'Edit', 'View', 'Downloads', 'Window', 'Help'].map((m) => (
          <span key={m}>{m}</span>
        ))}
      </div>
      <div className="flex-1" />
      {state.settings.menuBar && (
        <button
          onClick={() => toggleMenu('extra')}
          title="Haul"
          className={cx('flex items-center gap-1.25 rounded-[5px] px-1.5 py-0.5', state.menu === 'extra' && 'glass')}
        >
          <svg
            viewBox="0 0 20 20"
            className="size-4.25 -rotate-90 fill-none stroke-current"
            style={{ strokeWidth: 1.8 }}
          >
            <circle cx="10" cy="10" r="8" strokeOpacity={0.25} />
            <circle
              cx="10"
              cy="10"
              r="8"
              strokeLinecap="round"
              strokeDasharray={`${(overall(demo) * RING).toFixed(2)} ${RING.toFixed(2)}`}
            />
            <path
              d="M10 6v7M7.3 10.6L10 13.3l2.7-2.7"
              transform="rotate(90 10 10)"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
          {running.length > 0 && <span className="text-xs tabular-nums">{fmtBytes(speed)}/s</span>}
        </button>
      )}
      <Glyph d="M2.5 9a14 14 0 0 1 19 0M5.8 12.6a9 9 0 0 1 12.4 0M9.2 16.1a4 4 0 0 1 5.6 0M12 19.5v.1" width={2} />
      <div className="flex items-center gap-px">
        <div className="h-2.75 w-5.5 rounded-[3.5px] border border-current p-px opacity-90">
          <div className="h-full w-[72%] rounded-[1.5px] bg-current" />
        </div>
        <div className="h-1 w-[1.5px] rounded-[1px] bg-current opacity-60" />
      </div>
      <span className="tabular-nums">{clock}</span>
    </div>
  )
}

/// The Haul menu, with the app's commands (HaulApp.swift's HaulCommands).
export function AppMenu({ demo }: { demo: Demo }) {
  const { update } = demo
  const close = () => update(() => ({ menu: null }))
  const items: ([string, string, () => void] | null)[] = [
    ['About Haul', '', () => demo.openSettings('about')],
    [
      'Check for Updates…',
      '',
      () => {
        demo.openSettings('general')
        update(() => ({ checkingUntil: Date.now() + 1500 }))
      },
    ],
    null,
    ['Settings…', '⌘,', () => demo.openSettings()],
    null,
    ['Add Download…', '⌘N', demo.openAdd],
    [
      'Pause All',
      '⌥⌘P',
      () => {
        demo.pauseAll()
        close()
      },
    ],
    [
      'Resume All',
      '⌥⌘R',
      () => {
        demo.resumeAll()
        close()
      },
    ],
    ['Clear Completed…', '', demo.clearCompleted],
    null,
    ['Show Main Window', '⌘0', () => update(() => ({ menu: null, winOpen: true, front: 'main' }))],
  ]
  return (
    <div className="glass absolute top-7 left-3 z-50 flex w-62.5 flex-col rounded-xl p-1.25 shadow-menu">
      {items.map((item, i) =>
        item ? (
          <button
            key={item[0]}
            onClick={item[2]}
            className="group flex h-6 items-center justify-between rounded-md px-2.25 text-left hover:bg-accent hover:text-white"
          >
            <span>{item[0]}</span>
            <span className="text-text3 group-hover:text-white/80">{item[1]}</span>
          </button>
        ) : (
          <div key={i} className="mx-2 my-1 h-[.5px] bg-sep" />
        ),
      )}
    </div>
  )
}

/// The menu bar extra's window (MenuBarView.swift's MenuBarPopover).
export function MenuBarPopover({ demo }: { demo: Demo }) {
  const { state, update } = demo
  const unfinished = state.items.filter(isUnfinished)
  const recent = state.items.filter((d) => d.status === 'completed').slice(0, 3)
  const running = state.items.some((d) => d.status === 'downloading')
  const open = (sel?: number) =>
    update(() => ({ menu: null, winOpen: true, front: 'main', ...(sel ? { sel, filter: 'all' } : {}) }))

  return (
    <div className="glass absolute top-7.5 right-37.5 z-50 flex w-80 flex-col overflow-hidden rounded-2xl shadow-[0_0_0_.5px_var(--glassB),0_16px_44px_rgba(0,0,0,.28)]">
      <div className="flex items-baseline justify-between px-3.5 pt-3 pb-2">
        <span className="font-bold">Haul</span>
        <span className="text-[11px] text-text2 tabular-nums">{subtitle(demo)}</span>
      </div>
      <div className="flex flex-col px-1.5">
        {unfinished.length === 0 && <div className="px-2 py-3.5 text-xs text-text3">No active downloads.</div>}
        {unfinished.slice(0, 4).map((d) => (
          <div key={d.id} className="flex items-center gap-2.5 rounded-lg px-2 py-1.75 hover:bg-hover">
            <FileIcon kind={d.kind} width={20} height={25} band={8} radius={3} />
            <div className="flex min-w-0 flex-1 flex-col gap-0.75">
              <span className="truncate text-xs font-medium">{d.name}</span>
              <Bar
                value={progress(d)}
                height={3}
                fill={d.status === 'downloading' ? 'var(--accent)' : 'var(--text3)'}
              />
              <span className="truncate text-[10.5px] text-text2 tabular-nums">{statusLine(d)}</span>
            </div>
            <button
              onClick={() => demo.toggle(d.id)}
              className="flex size-5 flex-none items-center justify-center rounded-full shadow-[inset_0_0_0_1.2px_var(--text3)]"
            >
              <Glyph d={d.status === 'downloading' ? ICON.pause : ICON.play} size={10} width={2.6} />
            </button>
          </div>
        ))}
      </div>
      {recent.length > 0 && (
        <>
          <div className="px-3.5 pt-2.5 pb-1 text-[11px] font-semibold text-text3">Recently finished</div>
          <div className="flex flex-col px-1.5 pb-1.5">
            {recent.map((d) => (
              <button
                key={d.id}
                onClick={() => open(d.id)}
                className="flex items-center gap-2.5 rounded-lg px-2 py-1.5 text-left hover:bg-hover"
              >
                <FileIcon kind={d.kind} width={20} height={25} band={8} radius={3} />
                <span className="min-w-0 flex-1 truncate text-xs">{d.name}</span>
                <span className="text-[11px] text-text2">{fmtBytes(d.size)}</span>
              </button>
            ))}
          </div>
        </>
      )}
      <div className="flex gap-1.5 border-t-[.5px] border-sep px-3 pt-2.5 pb-3">
        <Pill small className="flex-1" onClick={running ? demo.pauseAll : demo.resumeAll}>
          {running ? 'Pause All' : 'Resume All'}
        </Pill>
        <Pill small className="flex-1" onClick={demo.openAdd}>
          Add Link…
        </Pill>
        <Pill small prominent className="flex-1" onClick={() => open()}>
          Open Haul
        </Pill>
      </div>
    </div>
  )
}

/// "Remove …?" alert, shown while "Ask before removing downloads" is on.
export function RemoveAlert({ demo }: { demo: Demo }) {
  const { state, update } = demo
  const d = state.items.find((x) => x.id === state.confirmRemove)
  if (!d) return null
  const detail =
    d.status === 'completed'
      ? `The file stays in ${folderFor(state.settings, d.kind)}.`
      : "What's been downloaded so far will be deleted."
  const cancel = () => update(() => ({ confirmRemove: null }))
  return (
    <>
      <div className="absolute inset-0 z-54" onMouseDown={cancel} />
      <div className="glass absolute top-55 left-1/2 z-55 -ml-32.5 flex w-65 animate-sheet-in flex-col items-center gap-2 rounded-2xl px-4 pt-5 pb-4 text-center shadow-[0_0_0_.5px_var(--glassB),0_20px_50px_rgba(0,0,0,.3)]">
        <AppTile size={48} radius={11} glyph={28} />
        <div className="mt-1 font-bold wrap-break-word">Remove “{d.name}”?</div>
        <div className="text-[11px] text-text2">{detail}</div>
        <button
          onClick={() => {
            demo.setSetting('confirmRemove', false)
            demo.remove(d.id)
          }}
          className="mt-1 text-[11px] text-text2 underline-offset-2 hover:underline"
        >
          Don't ask again
        </button>
        <div className="mt-1 flex w-full flex-col gap-1.5">
          <Pill prominent className="w-full bg-red" onClick={() => demo.remove(d.id)}>
            Remove
          </Pill>
          <Pill className="w-full" onClick={cancel}>
            Cancel
          </Pill>
        </div>
      </div>
    </>
  )
}

export function Notifications({ demo }: { demo: Demo }) {
  const { state, update } = demo
  return (
    <div className="pointer-events-none absolute top-9 right-3 z-60 flex w-85 flex-col gap-2">
      {state.notes.map((n) => (
        <div
          key={n.key}
          onClick={() => {
            update(() => ({ winOpen: true, front: 'main', sel: n.itemId, filter: 'all' }))
            demo.dismissNote(n.key)
          }}
          className="glass pointer-events-auto relative flex animate-note-in items-center gap-2.5 rounded-[18px] px-3 py-2.75 shadow-[0_0_0_.5px_var(--glassB),0_10px_30px_rgba(0,0,0,.2)]"
        >
          <AppTile size={34} radius={9} glyph={20} />
          <div className="flex min-w-0 flex-1 flex-col gap-px">
            <div className="flex items-baseline justify-between">
              <span className="text-[12.5px] font-semibold">{n.title}</span>
              <span className="text-[11px] text-text2">now</span>
            </div>
            <span className="truncate text-xs">{n.name}</span>
            <span className="text-[11px] text-text2">{n.sub}</span>
          </div>
          <button
            onClick={(e) => {
              e.stopPropagation()
              demo.dismissNote(n.key)
            }}
            className="absolute -top-1.25 -left-1.25 flex size-4.5 items-center justify-center rounded-full bg-win shadow-ctl"
            aria-label="Close"
          >
            <Glyph d={ICON.close} size={9} width={2.6} />
          </button>
        </div>
      ))}
    </div>
  )
}

export function Dock({ demo }: { demo: Demo }) {
  const { state, update } = demo
  const running = state.items.filter((d) => d.status === 'downloading').length
  const showProgress = state.settings.dockProgress && running > 0
  const bouncing = state.now < state.bounceUntil
  const tile = 'size-12.5 rounded-xl shadow-[inset_0_0_0_.5px_rgba(0,0,0,.15)]'

  return (
    <div className="glass absolute bottom-2 left-1/2 z-30 flex -translate-x-1/2 items-end gap-2.5 rounded-3xl px-2.5 py-1.75 shadow-[0_0_0_.5px_var(--glassB),0_10px_30px_rgba(0,0,0,.18)]">
      <div title="Finder" className={tile} style={{ background: 'linear-gradient(180deg,#7cc4f5,#2f8ee6)' }} />
      <div title="Browser" className={tile} style={{ background: 'linear-gradient(180deg,#f5f5f7,#d9dce2)' }} />
      <div title="Mail" className={tile} style={{ background: 'linear-gradient(180deg,#68b5ff,#1b6fe0)' }} />
      <div className="flex flex-col items-center gap-0.75">
        <button
          title="Haul"
          onClick={() => update(() => ({ winOpen: true, front: 'main' }))}
          className="relative transition-transform duration-300 ease-[cubic-bezier(.3,1.6,.5,1)]"
          style={{ transform: `translateY(${bouncing ? -14 : 0}px)` }}
        >
          <AppTile size={50} radius={12} glyph={30} />
          {showProgress && (
            <div className="absolute inset-x-1.25 bottom-1.25 h-1.75 rounded bg-white/92 p-[1.5px] shadow-[0_0_0_.5px_rgba(0,0,0,.2)]">
              <div
                className="h-full rounded-[3px] bg-accent transition-[width] duration-500 ease-linear"
                style={{ width: `${(overall(demo) * 100).toFixed(2)}%` }}
              />
            </div>
          )}
          {showProgress && (
            <div className="absolute -top-1.25 -right-1.5 flex h-5 min-w-5 items-center justify-center rounded-[10px] bg-[#ff3b30] px-1.25 text-xs font-semibold text-white shadow-[0_1px_3px_rgba(0,0,0,.25)]">
              {running}
            </div>
          )}
        </button>
        <div className="size-1 rounded-full bg-text" />
      </div>
      <div className="mx-0.5 mt-1 mb-2.5 w-[.5px] self-stretch bg-text3" />
      <div
        title="Downloads"
        className={cx(tile, 'flex items-center justify-center text-white')}
        style={{ background: 'linear-gradient(180deg,#9ccdf6,#5aa6ea)' }}
      >
        <Glyph d={ICON.download} size={24} width={2.2} />
      </div>
      <div
        title="Trash"
        className="flex size-12.5 items-center justify-center rounded-xl bg-white/25 text-text2 shadow-[inset_0_0_0_.5px_var(--glassB)]"
      >
        <Glyph d="M5 7h14M9.5 7V5h5v2M7 7l1 12h8l1-12" size={24} width={1.6} />
      </div>
    </div>
  )
}
