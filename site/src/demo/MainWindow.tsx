import { useEffect, useRef } from 'react'
import { links } from '../links'
import { Bar, Checkbox, cx, FileIcon, Glyph, Group, ICON, Pill, PopUp, Segmented } from './controls'
import {
  fmtBytes,
  fmtDuration,
  folderFor,
  hourLabel,
  inSchedule,
  KINDS,
  progress,
  STATUS_LABEL,
  statusLine,
  type Download,
  type Filter,
  type Kind,
} from './model'
import { addCandidates, splitNew, type Demo } from './useDemo'

const LIBRARY: [Filter, string][] = [
  ['all', 'All Downloads'],
  ['active', 'Active'],
  ['queued', 'Queued'],
  ['completed', 'Completed'],
  ['failed', 'Failed'],
]
const KIND_KEYS = Object.keys(KINDS) as Kind[]

export const matches = (f: Filter) => (d: Download) =>
  f === 'all'
    ? true
    : f === 'active'
      ? d.status === 'downloading' || d.status === 'paused'
      : f === 'queued' || f === 'completed' || f === 'failed'
        ? d.status === f
        : d.kind === f

export const filterTitle = (f: Filter) => LIBRARY.find(([k]) => k === f)?.[1] ?? KINDS[f as Kind].sidebar

/// Header subtitle, as DownloadStore.subtitle words it.
export function subtitle(demo: Demo) {
  const { items, settings } = demo.state
  const running = items.filter((d) => d.status === 'downloading')
  if (running.length) return `${running.length} downloading · ${fmtBytes(running.reduce((a, d) => a + d.speed, 0))}/s`
  const queued = items.filter((d) => d.status === 'queued').length
  if (
    queued &&
    settings.scheduleOnly &&
    !inSchedule(new Date().getHours(), settings.scheduleFrom, settings.scheduleTo)
  ) {
    return `${queued} queued · starts at ${hourLabel(settings.scheduleFrom)}`
  }
  return `${queued} queued · idle`
}

export function visibleRows(demo: Demo) {
  const { items, filter, query } = demo.state
  const q = query.trim().toLowerCase()
  return items.filter(matches(filter)).filter((d) => !q || d.name.toLowerCase().includes(q) || d.host.includes(q))
}

function TrafficLights({ onClose }: { onClose: () => void }) {
  return (
    <div className="flex gap-2">
      <button
        onClick={onClose}
        className="size-3 rounded-full bg-[#ff5f57] shadow-[inset_0_0_0_.5px_rgba(0,0,0,.15)]"
        aria-label="Close"
      />
      <button
        onClick={onClose}
        className="size-3 rounded-full bg-[#febc2e] shadow-[inset_0_0_0_.5px_rgba(0,0,0,.15)]"
        aria-label="Minimize"
      />
      <span className="size-3 rounded-full bg-[#28c840] shadow-[inset_0_0_0_.5px_rgba(0,0,0,.15)]" />
    </div>
  )
}

const capsule = 'flex h-7 items-center justify-center rounded-[14px] bg-ctl shadow-ctl'

export function MainWindow({ demo }: { demo: Demo }) {
  const { state, update } = demo
  const close = () => update(() => ({ winOpen: false, addOpen: false }))

  return (
    <div
      onMouseDown={() => state.front !== 'main' && update(() => ({ front: 'main' }))}
      className="absolute top-12.5 left-1/2 flex h-180 w-295 -translate-x-1/2 overflow-hidden rounded-[18px] bg-win shadow-window"
      style={{ zIndex: state.front === 'main' ? 12 : 10 }}
    >
      {state.showSidebar && <Sidebar demo={demo} onClose={close} />}
      <div className="relative flex min-w-0 flex-1 flex-col">
        <Toolbar demo={demo} onClose={close} />
        <div className="flex min-h-0 flex-1">
          <List demo={demo} />
          {state.showInspector && <Inspector demo={demo} />}
        </div>
        <StatusBar demo={demo} />
      </div>
      {state.addOpen && <AddPanel demo={demo} />}
    </div>
  )
}

function Sidebar({ demo, onClose }: { demo: Demo; onClose: () => void }) {
  const { state, update } = demo
  const item = (key: Filter, label: string, icon: string) => {
    const n = state.items.filter(matches(key)).length
    return (
      <button
        key={key}
        onClick={() => update(() => ({ filter: key }))}
        className={cx('flex h-7 items-center gap-2 rounded-[7px] px-2 text-left', state.filter === key && 'bg-selg')}
      >
        <Glyph d={icon} width={1.7} className="text-accent" />
        <span className="flex-1">{label}</span>
        {n > 0 && <span className="text-xs text-text3 tabular-nums">{n}</span>}
      </button>
    )
  }

  return (
    <div className="my-2 ml-2 flex w-52 flex-none flex-col overflow-hidden rounded-xl bg-side shadow-[0_0_0_.5px_var(--sep)]">
      <div className="flex h-11 flex-none items-center px-3">
        <TrafficLights onClose={onClose} />
      </div>
      <div className="flex flex-1 flex-col gap-px overflow-auto px-2.5 pt-1 pb-2.5">
        <div className="px-2 pt-1.5 pb-1 text-[11px] font-semibold text-text3">Library</div>
        {LIBRARY.map(([key, label]) => item(key, label, ICON[key as keyof typeof ICON]))}
        <div className="px-2 pt-3.5 pb-1 text-[11px] font-semibold text-text3">Kinds</div>
        {KIND_KEYS.map((k) => item(k, KINDS[k].sidebar, ICON[k]))}
      </div>
      <a
        href={links.sponsor}
        target="_blank"
        rel="noreferrer"
        title="Support Haul on GitHub Sponsors"
        className="mb-1.5 flex h-7 items-center gap-1.5 px-3.5 text-xs text-text3! hover:text-text2!"
      >
        <Glyph d={ICON.heart} size={11} width={1.7} className="text-red" style={{ fill: 'currentColor' }} />
        Sponsor
      </a>
      <div className="flex flex-col gap-1.5 border-t-[.5px] border-sep px-3.5 pt-2.5 pb-3 text-[11px] text-text2">
        <div className="flex justify-between">
          <span>Macintosh HD</span>
          <span>214 GB free</span>
        </div>
        <div className="h-1 overflow-hidden rounded-sm bg-track">
          <div className="h-full w-[58%] bg-text3" />
        </div>
      </div>
    </div>
  )
}

function Toolbar({ demo, onClose }: { demo: Demo; onClose: () => void }) {
  const { state, update, setSetting } = demo
  const { settings } = state
  return (
    <div className="flex h-13 flex-none items-center gap-2.5 pr-3 pl-3.5">
      {!state.showSidebar && (
        <div className="mr-1.5">
          <TrafficLights onClose={onClose} />
        </div>
      )}
      <button
        title="Toggle Sidebar"
        onClick={() => update((s) => ({ showSidebar: !s.showSidebar }))}
        className={cx(capsule, 'w-8')}
      >
        <Glyph d={ICON.sidebarLeft} width={1.7} />
      </button>
      <div className="ml-1 flex min-w-0 flex-col">
        <b className="text-sm leading-4.25">{filterTitle(state.filter)}</b>
        <span className="text-[11px] leading-3.5 whitespace-nowrap text-text2 tabular-nums">{subtitle(demo)}</span>
      </div>
      <div className="flex-1" />
      <button
        title="Speed Limit"
        onClick={() => setSetting('limitOn', !settings.limitOn)}
        className={cx(capsule, 'gap-1.25 px-2.5', settings.limitOn && 'text-accent')}
      >
        <Glyph d={ICON.gauge} />
        <span className="text-xs font-medium whitespace-nowrap">
          {settings.limitOn ? `${settings.limitMBps} MB/s` : 'No Limit'}
        </span>
      </button>
      <div className={cx(capsule, 'px-0.5')}>
        <button title="Pause All" onClick={demo.pauseAll} className="flex h-7 w-8 items-center justify-center">
          <Glyph d={ICON.pause} size={15} width={2.2} />
        </button>
        <div className="h-3.5 w-[.5px] bg-ctl-border" />
        <button title="Resume All" onClick={demo.resumeAll} className="flex h-7 w-8 items-center justify-center">
          <Glyph d={ICON.play} size={15} width={1} style={{ fill: 'currentColor' }} />
        </button>
      </div>
      <button title="Add Download (⌘N)" onClick={demo.openAdd} className={cx(capsule, 'w-8')}>
        <Glyph d={ICON.plus} width={2} />
      </button>
      <div className={cx(capsule, 'w-45 justify-start gap-1.5 px-2.5')}>
        <Glyph d={ICON.search} size={14} width={2} className="text-text2" />
        <input
          value={state.query}
          onChange={(e) => update(() => ({ query: e.target.value }))}
          placeholder="Search"
          className="min-w-0 flex-1 border-0 bg-transparent outline-none placeholder:text-text3"
        />
      </div>
      <button
        title="Toggle Inspector"
        onClick={() => update((s) => ({ showInspector: !s.showInspector }))}
        className={cx(capsule, 'w-8', state.showInspector && 'text-accent')}
      >
        <Glyph d={ICON.sidebarRight} width={1.7} />
      </button>
    </div>
  )
}

function List({ demo }: { demo: Demo }) {
  const { state, update } = demo
  const rows = visibleRows(demo)
  const queue = state.items.filter((d) => d.status === 'queued')

  return (
    <div className="min-w-0 flex-1 overflow-auto px-2 pt-0.5 pb-2">
      {rows.map((d) => {
        const selected = d.id === state.sel
        const action =
          d.status === 'downloading'
            ? [ICON.pause, 'Pause']
            : d.status === 'failed'
              ? [ICON.retry, 'Retry']
              : d.status === 'completed'
                ? null
                : [ICON.play, 'Resume']
        const fg2 = selected ? 'rgba(255,255,255,.78)' : d.status === 'failed' ? 'var(--red)' : 'var(--text2)'
        const position = d.status === 'queued' ? queue.indexOf(d) + 1 : undefined
        return (
          <div
            key={d.id}
            onClick={() => update(() => ({ sel: d.id }))}
            onDoubleClick={() => demo.toggle(d.id)}
            className={cx(
              'flex min-h-11.5 items-center gap-2.5 rounded-lg px-2.5 py-1.25',
              selected && 'bg-accent text-white',
            )}
          >
            <FileIcon name={d.name} kind={d.kind} width={24} height={30} band={10} fontSize={6.5} radius={4} />
            <div className="flex min-w-0 flex-1 flex-col gap-0.75">
              <span className="truncate font-medium">{d.name}</span>
              {(d.status === 'downloading' || d.status === 'paused') && (
                <Bar
                  value={progress(d)}
                  height={4}
                  fill={selected ? '#fff' : d.status === 'paused' ? 'var(--text3)' : 'var(--accent)'}
                  track={selected ? 'rgba(255,255,255,.3)' : undefined}
                />
              )}
              <span className="truncate text-[11px] tabular-nums" style={{ color: fg2 }}>
                {statusLine(d, position)}
              </span>
            </div>
            {action ? (
              <button
                title={action[1]}
                onClick={(e) => {
                  e.stopPropagation()
                  demo.toggle(d.id)
                }}
                className="flex size-5.5 flex-none items-center justify-center rounded-full"
                style={{ boxShadow: `inset 0 0 0 1.2px ${fg2}` }}
              >
                <Glyph d={action[0]} size={11} width={2.6} />
              </button>
            ) : (
              <span className="flex-none text-[11px]" style={{ color: fg2 }}>
                {d.added.replace('Today, ', '')}
              </span>
            )}
          </div>
        )
      })}
      {rows.length === 0 && (
        <div className="flex h-full flex-col items-center justify-center gap-1 text-text3">
          <span className="text-[15px] font-semibold">No Downloads</span>
          <span className="text-xs">Nothing matches this view.</span>
        </div>
      )}
    </div>
  )
}

function Inspector({ demo }: { demo: Demo }) {
  const { state, update } = demo
  const d = state.items.find((x) => x.id === state.sel)
  if (!d) {
    return (
      <div className="flex w-68 flex-none items-center justify-center border-l-[.5px] border-sep text-sm font-medium text-text3">
        No Selection
      </div>
    )
  }

  const p = progress(d)
  const segSize = d.size / d.segs.length
  const statusColor =
    { downloading: 'var(--accent)', failed: 'var(--red)', completed: 'var(--green)' }[d.status as string] ??
    'var(--text2)'
  const segColor =
    d.status === 'completed'
      ? 'var(--green)'
      : d.status === 'failed'
        ? 'var(--red)'
        : d.status === 'downloading'
          ? 'var(--accent)'
          : 'var(--text3)'
  const live = d.status === 'downloading' ? Math.max(1, d.segs.filter((v) => v < 1).length) : 0
  const connections = live
    ? `${live} of ${d.segs.length} connections`
    : `${d.segs.length} connection${d.segs.length === 1 ? '' : 's'}`
  const speed =
    d.status === 'downloading' && d.speed > 0
      ? `${fmtBytes(d.speed)}/s · ${fmtDuration((d.size * (1 - p)) / d.speed)} left`
      : d.status === 'completed'
        ? 'Done'
        : '—'
  const checksum: [string, string] =
    d.status !== 'completed'
      ? ['After download', 'var(--text2)']
      : d.sha256
        ? [`SHA-256 ${d.sha256.slice(0, 12)}…`, 'var(--green)']
        : ['Not computed', 'var(--text2)']
  const primary = {
    downloading: 'Pause',
    paused: 'Resume',
    queued: 'Start Now',
    failed: 'Retry',
    completed: 'Show in Finder',
  }[d.status]
  const copied = state.now < state.copiedUntil

  const detail = (label: string, value: React.ReactNode) => (
    <div className="flex items-baseline gap-2.5 px-2.5 py-2">
      <span className="w-15.5 flex-none text-text2">{label}</span>
      <span className="min-w-0 flex-1">{value}</span>
    </div>
  )

  return (
    <div className="flex w-68 flex-none flex-col overflow-auto border-l-[.5px] border-sep">
      <div className="flex flex-col items-center gap-2 px-4.5 pt-4.5 pb-4 text-center">
        <FileIcon name={d.name} kind={d.kind} width={52} height={64} band={20} fontSize={11} radius={7} />
        <div className="text-[13px] leading-4.25 font-semibold wrap-break-word text-pretty">{d.name}</div>
        <div className="text-[11px] text-text2">
          {KINDS[d.kind].label} · {fmtBytes(d.size)}
        </div>
      </div>

      <div className="flex flex-col gap-2 px-4 pb-3.5 text-[11px] tabular-nums">
        <div className="flex items-baseline justify-between">
          <span className="font-semibold" style={{ color: statusColor }}>
            {STATUS_LABEL[d.status]}
          </span>
          <span className="text-text2">{(p * 100).toFixed(1)}%</span>
        </div>
        <div className="grid grid-cols-8 gap-0.75">
          {d.segs.map((v, i) => (
            <div
              key={i}
              title={`Connection ${i + 1}: ${fmtBytes(v * segSize)} of ${fmtBytes(segSize)}`}
              className="flex h-5.5 items-end overflow-hidden rounded bg-track"
            >
              <div
                className="w-full transition-[height] duration-500 ease-linear"
                style={{ height: `${(v * 100).toFixed(1)}%`, background: segColor }}
              />
            </div>
          ))}
        </div>
        <div className="flex justify-between text-text2">
          <span>{connections}</span>
          <span>{speed}</span>
        </div>
      </div>

      <Group className="mx-3 text-xs">
        {detail(
          'Size',
          <span className="tabular-nums">
            {d.status === 'completed' ? fmtBytes(d.size) : `${fmtBytes(d.size * p)} of ${fmtBytes(d.size)}`}
          </span>,
        )}
        {detail('Source', d.host)}
        {detail(
          'Link',
          <span className="flex items-center gap-1.5">
            <span className="min-w-0 truncate text-accent" title={d.url}>
              {d.url}
            </span>
            {d.status !== 'completed' && (
              <span title="Update Link…" className="text-text2">
                <Glyph d={ICON.pencil} size={12} />
              </span>
            )}
          </span>,
        )}
        {detail('Saved to', folderFor(state.settings, d.kind))}
        {detail('Added', d.added)}
        {detail(
          'Checksum',
          <span className="block truncate" style={{ color: checksum[1] }} title={d.sha256 ?? ''}>
            {checksum[0]}
          </span>,
        )}
      </Group>

      <div className="flex flex-col gap-1.5 px-3 pt-3.5 pb-4">
        <Pill prominent onClick={() => (d.status === 'completed' ? update(() => ({})) : demo.toggle(d.id))}>
          {primary}
        </Pill>
        <div className="flex gap-1.5">
          <Pill small className="flex-1" onClick={() => demo.copyLink(d.url)}>
            {copied ? 'Copied' : 'Copy Link'}
          </Pill>
          <Pill small className="flex-1 text-red" onClick={() => demo.requestRemove(d.id)}>
            Remove
          </Pill>
        </div>
      </div>
    </div>
  )
}

function StatusBar({ demo }: { demo: Demo }) {
  const { settings, items } = demo.state
  const count = visibleRows(demo).length
  const speed = fmtBytes(items.filter((d) => d.status === 'downloading').reduce((a, d) => a + d.speed, 0))
  return (
    <div className="flex h-6.5 flex-none items-center gap-3.5 border-t-[.5px] border-sep px-3.5 text-[11px] text-text2 tabular-nums">
      <span>
        {count} item{count === 1 ? '' : 's'}
      </span>
      <div className="flex-1" />
      <span>{settings.limitOn ? `Limited to ${settings.limitMBps} MB/s · ↓ ${speed}/s` : `↓ ${speed}/s`}</span>
    </div>
  )
}

function AddPanel({ demo }: { demo: Demo }) {
  const { state, update } = demo
  const input = useRef<HTMLInputElement>(null)
  useEffect(() => {
    input.current?.focus({ preventScroll: true })
    input.current?.select()
  }, [])

  const candidates = addCandidates(state.addText)
  const fresh = splitNew(state)
  const single = candidates.length === 1 ? candidates[0] : null
  const existing = single && state.items.find((d) => d.url === single.url)
  const blockedWebPage = single?.isWebPage && state.settings.skipWebPages
  const batch = candidates.length > 1
  const folder = batch
    ? state.settings.autoSort
      ? 'Downloads, by kind'
      : 'Downloads'
    : folderFor(state.settings, single?.kind ?? 'doc')
  const cta = batch
    ? `Add ${fresh.length} Download${fresh.length === 1 ? '' : 's'}`
    : state.addStart
      ? 'Download'
      : 'Add to Queue'

  return (
    <>
      <div className="absolute inset-0 z-5 bg-black/12" onMouseDown={() => update(() => ({ addOpen: false }))} />
      <div className="absolute top-16 left-1/2 z-6 -ml-57.5 flex w-115 animate-sheet-in flex-col gap-3.5 rounded-2xl bg-win px-4.5 pt-4.5 pb-4 shadow-window">
        <div className="text-sm font-bold">Add Download</div>
        <div className="flex flex-col gap-1.5">
          <span className="text-xs text-text2">Address</span>
          <input
            ref={input}
            value={state.addText}
            onChange={(e) => update(() => ({ addText: e.target.value }))}
            placeholder="Paste a link, or several at once"
            className="h-7 rounded-[7px] border-0 bg-field px-2.25 shadow-[inset_0_0_0_.5px_var(--ctlB)] outline-none placeholder:text-text3"
          />
        </div>

        {single && (
          <div className="flex items-center gap-2.5 rounded-[10px] bg-group p-2.5">
            <FileIcon name={single.name} kind={single.kind} width={28} height={34} band={11} fontSize={7} radius={4} />
            <div className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="truncate font-medium">{single.name}</span>
              {blockedWebPage ? (
                <span className="text-[11px] text-red">This link opens a web page, not a file.</span>
              ) : (
                <span className="text-[11px] text-text2">
                  {KINDS[single.kind].label} · {fmtBytes(single.size)} · {single.host}
                </span>
              )}
            </div>
          </div>
        )}
        {batch && (
          <div className="flex flex-col gap-1 rounded-[10px] bg-group p-2.5">
            <span className="text-xs font-semibold">{candidates.length} links</span>
            {candidates.slice(0, 4).map((c) => (
              <div key={c.url} className="flex items-center gap-2 text-xs">
                <FileIcon kind={c.kind} width={14} height={17} band={5} radius={2} />
                <span className="min-w-0 flex-1 truncate">{c.name}</span>
                <span className="text-[11px] text-text2">
                  {state.items.some((d) => d.url === c.url) ? 'In list' : c.host}
                </span>
              </div>
            ))}
            {candidates.length > 4 && <span className="text-[11px] text-text2">and {candidates.length - 4} more</span>}
          </div>
        )}
        {!candidates.length && state.addText.trim() && (
          <div className="text-xs text-text3">Enter a valid http(s) link.</div>
        )}
        {existing && (
          <div className="flex items-center gap-2 text-xs text-text2">
            <Glyph d={ICON.warning} size={14} className="text-orange" />
            This link is already in your list ({STATUS_LABEL[existing.status].toLowerCase()}).
          </div>
        )}

        <div className="grid grid-cols-[96px_1fr] items-center gap-y-2.5">
          <span className="text-text2">Save to</span>
          <div className="justify-self-start">
            <PopUp
              options={[[folder, `${folder} (Default)`]]}
              value={folder}
              onChange={() => {}}
              icon={<Glyph d={ICON.folder} size={14} className="text-accent" />}
            />
          </div>
          <span className="text-text2">Connections</span>
          <div className="justify-self-start">
            <Segmented
              options={[1, 4, 8, 16].map((n) => [n, String(n)] as [number, string])}
              value={state.addConns}
              onChange={(v) => update(() => ({ addConns: v }))}
              minWidth={38}
            />
          </div>
          <span />
          <div className="justify-self-start">
            <Checkbox on={state.addStart} onChange={(on) => update(() => ({ addStart: on }))}>
              Start immediately
            </Checkbox>
          </div>
        </div>

        <div className="mt-1 flex justify-end gap-2">
          <Pill onClick={() => update(() => ({ addOpen: false }))}>Cancel</Pill>
          <Pill prominent disabled={!fresh.length} onClick={demo.confirmAdd}>
            {cta}
          </Pill>
        </div>
      </div>
    </>
  )
}
