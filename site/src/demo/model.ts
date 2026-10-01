// Simulated download list and settings for the interactive demo. Labels, defaults and
// status lines mirror the macOS app (Haul/Models.swift, AppSettings.swift, DownloadRow.swift).

export const MB = 1024 * 1024
export const GB = MB * 1024

export type Kind = 'video' | 'audio' | 'image' | 'doc' | 'archive' | 'app'
export type Status = 'downloading' | 'paused' | 'queued' | 'failed' | 'completed'
export type Filter = 'all' | 'active' | 'queued' | 'completed' | 'failed' | Kind

export const KINDS: Record<Kind, { color: string; label: string; folder: string; sidebar: string }> = {
  video: { color: '#7a5af5', label: 'Movie', folder: 'Movies', sidebar: 'Movies' },
  audio: { color: '#e5487f', label: 'Audio', folder: 'Music', sidebar: 'Music' },
  image: { color: '#e8673a', label: 'Image', folder: 'Pictures', sidebar: 'Images' },
  doc: { color: '#3478f6', label: 'Document', folder: 'Documents', sidebar: 'Documents' },
  archive: { color: '#9a8468', label: 'Archive', folder: 'Archives', sidebar: 'Archives' },
  app: { color: '#5d6878', label: 'Installer', folder: 'Apps', sidebar: 'Apps' },
}

export const STATUS_LABEL: Record<Status, string> = {
  downloading: 'Downloading',
  paused: 'Paused',
  queued: 'Queued',
  failed: 'Failed',
  completed: 'Completed',
}

const EXT: Record<string, Kind> = {
  mp4: 'video',
  mov: 'video',
  mkv: 'video',
  webm: 'video',
  jpg: 'image',
  png: 'image',
  heic: 'image',
  pdf: 'doc',
  key: 'doc',
  epub: 'doc',
  docx: 'doc',
  mp3: 'audio',
  flac: 'audio',
  wav: 'audio',
  zip: 'archive',
  gz: 'archive',
  iso: 'archive',
  xip: 'archive',
  dmg: 'app',
  pkg: 'app',
}

export const extOf = (name: string) => name.toLowerCase().match(/\.([a-z0-9]+)$/)?.[1] ?? ''
export const kindOf = (name: string): Kind => EXT[extOf(name)] ?? 'doc'

export const fmtBytes = (b: number) =>
  b >= GB
    ? (b / GB).toFixed(b >= 10 * GB ? 1 : 2) + ' GB'
    : b >= MB
      ? (b / MB).toFixed(1) + ' MB'
      : Math.max(0, Math.round(b / 1024)) + ' KB'

export const fmtDuration = (s: number) => {
  if (!isFinite(s)) return '—'
  s = Math.ceil(s)
  if (s < 60) return s + ' sec'
  const m = Math.round(s / 60)
  return m < 60 ? m + ' min' : Math.floor(m / 60) + ' hr ' + (m % 60) + ' min'
}

export const hourLabel = (h: number) =>
  new Date(2000, 0, 1, h).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })

export const clockTime = () => new Date().toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })

/// Same rule as AppSettings.inSchedule: equal start and end means all day; wraps past midnight.
export const inSchedule = (hour: number, from: number, to: number) =>
  from === to ? true : from < to ? hour >= from && hour < to : hour >= from || hour < to

export type Download = {
  id: number
  name: string
  size: number
  status: Status
  host: string
  url: string
  kind: Kind
  added: string
  /// Per-connection progress, 0…1.
  segs: number[]
  speed: number
  /// Top speed this download reaches when unthrottled.
  max: number
  sha256: string | null
  error: string | null
}

// Fixed offsets so segments look like they started at slightly different times.
const OFFSETS = [0.1, -0.08, 0.05, -0.12, 0.09, -0.04, 0.02, -0.02, 0.06, -0.06, 0.03, -0.03, 0.07, -0.07, 0.01, -0.01]
export const makeSegs = (p: number, n: number) =>
  Array.from({ length: n }, (_, i) => (p >= 1 ? 1 : p <= 0 ? 0 : Math.min(1, Math.max(0, p + OFFSETS[i]))))
export const progress = (d: Download) => d.segs.reduce((a, b) => a + b, 0) / d.segs.length

/// A stable fake SHA-256 for a file name.
export function fakeHash(name: string) {
  let h = 2166136261
  let out = ''
  for (let i = 0; out.length < 64; i++) {
    h = Math.imul(h ^ name.charCodeAt(i % name.length) ^ i, 16777619)
    out += (h >>> 0).toString(16).padStart(8, '0')
  }
  return out.slice(0, 64)
}

export function seed(): Download[] {
  const rows: [string, number, number, Status, string, string, string, number, number][] = [
    [
      'Blender-4.5.3-macos-arm64.dmg',
      412.6 * MB,
      0.9,
      'downloading',
      'download.blender.org',
      '/release/Blender4.5/',
      'Today, 10:41',
      8,
      9 * MB,
    ],
    [
      'ubuntu-24.04.3-desktop-amd64.iso',
      6.1 * GB,
      0.38,
      'downloading',
      'releases.ubuntu.com',
      '/24.04.3/',
      'Today, 10:12',
      8,
      13 * MB,
    ],
    [
      'Field Recordings – Lisbon.flac',
      186 * MB,
      0.33,
      'paused',
      'files.soundarchive.org',
      '/2026/lisbon/',
      'Today, 9:58',
      4,
      5 * MB,
    ],
    [
      'Arctic Survey 2026 (4K).mov',
      2.4 * GB,
      0,
      'queued',
      'media.polarlab.org',
      '/survey/',
      'Today, 10:44',
      8,
      11 * MB,
    ],
    ['node-v22.20.0.pkg', 78.2 * MB, 0, 'queued', 'nodejs.org', '/dist/v22.20.0/', 'Today, 10:45', 4, 6 * MB],
    ['training-set-v2.tar.gz', 1.8 * GB, 0.61, 'failed', 'data.example.edu', '/sets/', 'Today, 8:20', 8, 10 * MB],
    ['Q3 Board Review.key', 48.3 * MB, 1, 'completed', 'share.northwind.co', '/d/8f2a/', 'Today, 8:02', 4, 0],
    [
      'Annual Report 2025.pdf',
      12.4 * MB,
      1,
      'completed',
      'investors.contoso.com',
      '/reports/',
      'Yesterday, 16:30',
      2,
      0,
    ],
    ['IBM-Plex-6.4.zip', 24.1 * MB, 1, 'completed', 'github.com', '/IBM/plex/releases/', 'Yesterday, 11:15', 4, 0],
    ['photo-export-0921.zip', 880 * MB, 1, 'completed', 'transfer.example.com', '/t/0921/', 'Sep 21', 8, 0],
    ['Episode 142 – Slow Software.mp3', 64.7 * MB, 1, 'completed', 'cdn.podhost.fm', '/ep/142/', 'Sep 19', 4, 0],
    ['IMG_4471.heic', 3.2 * MB, 1, 'completed', 'photos.example.com', '/s/4471/', 'Sep 18', 1, 0],
  ]
  return rows.map(([name, size, p, status, host, path, added, conns, max], i) => ({
    id: i + 1,
    name,
    size,
    status,
    host,
    added,
    url: 'https://' + host + path + encodeURIComponent(name),
    kind: kindOf(name),
    segs: makeSegs(p, conns),
    speed: status === 'downloading' ? max * 0.8 : 0,
    max: max || 8 * MB,
    sha256: status === 'completed' ? fakeHash(name) : null,
    error: status === 'failed' ? 'Connection reset by server' : null,
  }))
}

export type Appearance = 'light' | 'dark' | 'auto'
export type Accent = 'blue' | 'purple' | 'pink' | 'graphite'
export type ListCleanup = 'manually' | 'whenFinished' | 'day' | 'week' | 'month'

export const ACCENTS: Record<Accent, string> = {
  blue: '#0a7aff',
  purple: '#a24fd6',
  pink: '#e8437a',
  graphite: '#7d7d84',
}

export const LIST_CLEANUP: [ListCleanup, string][] = [
  ['manually', 'Manually'],
  ['whenFinished', 'When Finished'],
  ['day', 'After One Day'],
  ['week', 'After One Week'],
  ['month', 'After One Month'],
]

export const MAX_RETRIES = 3

/// Defaults match AppSettings.init.
export const defaultSettings = {
  appearance: 'auto' as Appearance,
  accent: 'blue' as Accent,
  menuBar: true,
  dockProgress: true,
  launchAtLogin: false,
  confirmRemove: true,
  removeFinished: 'manually' as ListCleanup,
  removeDeleted: true,
  checkForUpdates: true,
  notifyAdded: false,
  notify: true,
  notifyFailed: true,
  notifyOnlyInBackground: false,
  autoSort: true,
  computeChecksum: true,
  useServerDate: false,
  recordSource: true,
  maxConcurrent: 3,
  connections: 8,
  preventSleep: true,
  limitOn: false,
  limitMBps: 8,
  scheduleOnly: false,
  scheduleFrom: 1,
  scheduleTo: 7,
  pauseOnExpensive: true,
  autoRetry: true,
  skipWebPages: true,
}

export type Settings = typeof defaultSettings

export const folderFor = (s: Settings, kind: Kind) => (s.autoSort ? `Downloads/${KINDS[kind].folder}` : 'Downloads')

/// The line under a row's name, as DownloadRow.statusLine words it.
export function statusLine(d: Download, queuePosition?: number) {
  const done = fmtBytes(d.size * progress(d))
  const total = fmtBytes(d.size)
  switch (d.status) {
    case 'downloading':
      return d.speed > 0
        ? `${done} of ${total} — ${fmtBytes(d.speed)}/s, ${fmtDuration((d.size * (1 - progress(d))) / d.speed)} left`
        : `${done} of ${total} — connecting…`
    case 'paused':
      return `Paused — ${done} of ${total}`
    case 'queued':
      return `${queuePosition ? `Waiting — #${queuePosition} in queue` : 'Waiting'} · ${total}`
    case 'failed':
      return `Failed at ${Math.round(progress(d) * 100)}% — ${d.error ?? 'Unknown error'}`
    case 'completed':
      return `${total} — ${d.host}`
  }
}

export type ParsedLink = { name: string; host: string; size: number; kind: Kind; url: string; isWebPage: boolean }

/// Reads a typed link the way the Add panel does; only http(s) is accepted.
export function parseLink(text: string): ParsedLink | null {
  try {
    const url = new URL(text.trim())
    if (!/^https?:$/.test(url.protocol) || !url.hostname) return null
    const last = url.pathname.split('/').filter(Boolean).pop()
    const name = last ? decodeURIComponent(last) : url.hostname
    const ext = extOf(name)
    let h = 0
    for (const ch of url.href) h = (h * 31 + ch.charCodeAt(0)) | 0
    return {
      name,
      host: url.hostname,
      url: url.href,
      size: ((Math.abs(h) % 2900) + 20) * MB,
      kind: kindOf(name),
      isWebPage: !ext || ext === 'html' || ext === 'htm' || ext === 'php',
    }
  } catch {
    return null
  }
}
