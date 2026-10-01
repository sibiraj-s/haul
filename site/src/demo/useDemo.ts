import { useCallback, useEffect, useRef, useState } from 'react'
import {
  clockTime,
  defaultSettings,
  fakeHash,
  folderFor,
  fmtBytes,
  inSchedule,
  makeSegs,
  MB,
  parseLink,
  progress,
  seed,
  type Download,
  type Filter,
  type Settings,
} from './model'

export type Pane = 'general' | 'downloads' | 'network' | 'notifications' | 'about'
export type Note = { key: string; itemId: number; title: string; name: string; sub: string; at: number }

const TICK = 500
const NOTE_LIFETIME = 6500

function initialState() {
  return {
    items: seed(),
    sel: 1 as number | null,
    filter: 'all' as Filter,
    query: '',
    showSidebar: true,
    showInspector: true,
    winOpen: true,
    front: 'main' as 'main' | 'settings',
    addOpen: false,
    addText: 'https://mirror.example.net/films/sintel-2010-4k.mkv',
    addConns: defaultSettings.connections,
    addStart: true,
    settingsOpen: false,
    pane: 'general' as Pane,
    menu: null as 'app' | 'extra' | null,
    confirmRemove: null as number | null,
    notes: [] as Note[],
    settings: defaultSettings as Settings,
    bounceUntil: 0,
    copiedUntil: 0,
    checkingUntil: 0,
    now: Date.now(),
  }
}

export type DemoState = ReturnType<typeof initialState>

/// Notifications are skipped while the main window is in front, if Settings says so.
const canNotify = (s: DemoState) => !(s.settings.notifyOnlyInBackground && s.winOpen && s.front === 'main')

function note(itemId: number, title: string, name: string, sub: string, now: number): Note {
  return { key: `${itemId}-${title}-${now}`, itemId, title, name, sub, at: now }
}

/// Advances the simulation by one tick: starts queued items, moves bytes, finishes downloads.
function tick(prev: DemoState): DemoState {
  const now = Date.now()
  const s = { ...prev, now, notes: prev.notes.filter((n) => now - n.at < NOTE_LIFETIME) }
  const set = s.settings
  const items = s.items.map((d) => ({ ...d }))

  let active = items.filter((d) => d.status === 'downloading').length
  if (!set.scheduleOnly || inSchedule(new Date().getHours(), set.scheduleFrom, set.scheduleTo)) {
    for (const d of items) {
      if (d.status === 'queued' && active < set.maxConcurrent) {
        d.status = 'downloading'
        active++
      }
    }
  }

  const running = items.filter((d) => d.status === 'downloading')
  const limit = set.limitOn ? set.limitMBps * MB : Infinity
  let want = running.map((d) => d.speed * 0.75 + d.max * (0.6 + Math.random() * 0.4) * 0.25)
  const total = want.reduce((a, b) => a + b, 0)
  if (total > limit) want = want.map((w) => (w * limit) / total)

  const finished: Download[] = []
  const dt = TICK / 1000
  running.forEach((d, i) => {
    d.speed = want[i]
    const segSize = d.size / d.segs.length
    const open = d.segs.filter((v) => v < 1).length || 1
    d.segs = d.segs.map((v) =>
      v >= 1 ? 1 : Math.min(1, v + (((d.speed * dt) / open) * (0.5 + Math.random())) / segSize),
    )
    if (d.segs.every((v) => v >= 1)) {
      d.status = 'completed'
      d.speed = 0
      d.sha256 = set.computeChecksum ? fakeHash(d.name) : null
      d.added = 'Today, ' + clockTime()
      finished.push(d)
    }
  })

  s.items = set.removeFinished === 'whenFinished' ? items.filter((d) => !finished.includes(d)) : items
  if (finished.length) {
    s.bounceUntil = now + 600
    if (set.notify && canNotify(s)) {
      const added = finished.map((d) =>
        note(d.id, 'Download Finished', d.name, `${fmtBytes(d.size)} · ${folderFor(set, d.kind)}`, now),
      )
      s.notes = [...added, ...s.notes].slice(0, 3)
    }
  }
  if (s.sel !== null && !s.items.some((d) => d.id === s.sel)) s.sel = s.items[0]?.id ?? null
  return s
}

export function useDemo() {
  const [state, setState] = useState(initialState)
  const ref = useRef(state)
  ref.current = state

  useEffect(() => {
    const timer = setInterval(() => setState(tick), TICK)
    return () => clearInterval(timer)
  }, [])

  const update = useCallback((fn: (s: DemoState) => Partial<DemoState>) => setState((s) => ({ ...s, ...fn(s) })), [])

  const patchItem = (id: number, fn: (d: Download) => Partial<Download>) =>
    update((s) => ({ items: s.items.map((d) => (d.id === id ? { ...d, ...fn(d) } : d)) }))

  const actions = {
    update,
    setSetting: <K extends keyof Settings>(key: K, value: Settings[K]) =>
      update((s) => ({ settings: { ...s.settings, [key]: value } })),

    toggle: (id: number) =>
      patchItem(id, (d) => {
        switch (d.status) {
          case 'downloading':
            return { status: 'paused', speed: 0 }
          case 'failed':
            return { status: 'downloading', error: null }
          case 'paused':
          case 'queued':
            return { status: 'downloading' }
          default:
            return {}
        }
      }),

    pauseAll: () =>
      update((s) => ({
        items: s.items.map((d) => (d.status === 'downloading' ? { ...d, status: 'paused', speed: 0 } : d)),
      })),
    resumeAll: () =>
      update((s) => ({ items: s.items.map((d) => (d.status === 'paused' ? { ...d, status: 'downloading' } : d)) })),
    clearCompleted: () => update((s) => ({ items: s.items.filter((d) => d.status !== 'completed'), menu: null })),

    /// Asks first when "Ask before removing downloads" is on, like DownloadStore.requestRemove.
    requestRemove: (id: number) =>
      update((s) => (s.settings.confirmRemove ? { confirmRemove: id } : removeItem(s, id))),
    remove: (id: number) => update((s) => ({ ...removeItem(s, id), confirmRemove: null })),

    openAdd: () =>
      update((s) => ({ addOpen: true, winOpen: true, front: 'main', menu: null, addConns: s.settings.connections })),

    confirmAdd: () =>
      update((s) => {
        const links = splitNew(s)
        if (!links.length) return {}
        const now = Date.now()
        const created: Download[] = links.map((p, i) => ({
          id: now + i,
          ...p,
          status: s.addStart ? 'downloading' : 'queued',
          added: 'Today, ' + clockTime(),
          segs: makeSegs(0, s.addConns),
          speed: 0,
          max: (6 + Math.random() * 8) * MB,
          sha256: null,
          error: null,
        }))
        const notes =
          s.settings.notifyAdded && canNotify(s)
            ? [
                ...created.map((d) => note(d.id, 'Download Added', d.name, `${fmtBytes(d.size)} · ${d.host}`, now)),
                ...s.notes,
              ].slice(0, 3)
            : s.notes
        return { items: [...created, ...s.items], sel: created[0].id, addOpen: false, filter: 'all', query: '', notes }
      }),

    copyLink: (url: string) => {
      navigator.clipboard?.writeText(url).catch(() => {})
      update(() => ({ copiedUntil: Date.now() + 1200 }))
    },

    openSettings: (pane?: Pane) =>
      update((s) => ({ settingsOpen: true, front: 'settings', menu: null, pane: pane ?? s.pane })),

    dismissNote: (key: string) => update((s) => ({ notes: s.notes.filter((n) => n.key !== key) })),
  }

  return { state, ref, ...actions }
}

export type Demo = ReturnType<typeof useDemo>

function removeItem(s: DemoState, id: number): Partial<DemoState> {
  const index = s.items.findIndex((d) => d.id === id)
  const items = s.items.filter((d) => d.id !== id)
  return { items, sel: s.sel === id ? (items[Math.min(index, items.length - 1)]?.id ?? null) : s.sel }
}

/// Valid links in the Add panel that aren't already in the list (and aren't web pages, if skipped).
export function splitNew(s: DemoState) {
  const seen = new Set(s.items.map((d) => d.url))
  return addCandidates(s.addText)
    .filter((p) => !seen.has(p.url))
    .filter((p) => !(p.isWebPage && s.settings.skipWebPages))
}

export function addCandidates(text: string) {
  const unique = new Map<string, NonNullable<ReturnType<typeof parseLink>>>()
  // Splits on spaces and new lines, and on commas or semicolons between links.
  for (const w of text.split(/\s+/).flatMap((w) => w.split(/[,;](?=https?:\/\/)/))) {
    const p = parseLink(w.replace(/^[,;]+|[,;]+$/g, ''))
    if (p && !unique.has(p.url)) unique.set(p.url, p)
  }
  return [...unique.values()]
}

export const isUnfinished = (d: Download) =>
  d.status === 'downloading' || d.status === 'paused' || d.status === 'queued'
export { progress }
