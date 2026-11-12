import type { ReactNode } from 'react'
import { version } from '../../../package.json'
import { links } from '../links'
import { AppTile, cx, Glyph, Group, ICON, Pill, PopUp, Row, Segmented, Switch } from './controls'
import {
  ACCENTS,
  hourLabel,
  MAX_RETRIES,
  newPassword,
  PROXY_PORT,
  type Accent,
  type Appearance,
  type ListCleanup,
  type ProxyKind,
  type ProxyMode,
  type RemoteScope,
} from './model'
import type { Demo, Pane } from './useDemo'

// Mirrors SettingsView.Pane.
const PANES: [Pane, string, string][] = [
  ['general', 'General', ICON.gear],
  ['downloads', 'Downloads', ICON.download],
  ['network', 'Network', ICON.globe],
  ['remote', 'Remote', ICON.remote],
  ['notifications', 'Notifications', ICON.bell],
  ['extensions', 'Extensions', ICON.puzzle],
  ['about', 'About', ICON.info],
]

const HOURS = Array.from({ length: 24 }, (_, h) => [h, hourLabel(h)] as [number, string])

export function SettingsWindow({ demo }: { demo: Demo }) {
  const { state, update } = demo
  const title = PANES.find(([p]) => p === state.pane)![1]

  return (
    <div
      onMouseDown={() => state.front !== 'settings' && update(() => ({ front: 'settings' }))}
      className="absolute top-24 left-[calc(50%-220px)] flex max-h-175 w-140 flex-col overflow-hidden rounded-[18px] bg-win shadow-window"
      style={{ zIndex: state.front === 'settings' ? 12 : 10 }}
    >
      <div className="relative flex flex-col items-center border-b-[.5px] border-sep px-3 pt-2.5 pb-2">
        <div className="absolute top-3.5 left-3.5 flex gap-2">
          <button
            onClick={() => update(() => ({ settingsOpen: false }))}
            className="size-3 rounded-full bg-[#ff5f57]"
            aria-label="Close"
          />
          <span className="size-3 rounded-full bg-track" />
          <span className="size-3 rounded-full bg-track" />
        </div>
        <div className="mb-2 text-[13px] font-semibold">{title}</div>
        <div className="flex gap-1">
          {PANES.map(([pane, label, icon]) => (
            <button
              key={pane}
              onClick={() => update(() => ({ pane }))}
              className={cx(
                'flex h-12 w-18 flex-col items-center justify-center gap-0.75 rounded-[9px]',
                state.pane === pane ? 'bg-selg text-accent' : 'text-text2',
              )}
            >
              <Glyph d={icon} size={20} width={1.6} />
              <span className="text-[11px]">{label}</span>
            </button>
          ))}
        </div>
      </div>
      <div className="flex min-h-75 flex-col gap-3.5 overflow-y-auto px-5 pt-4 pb-5">
        {state.pane === 'general' && <General demo={demo} />}
        {state.pane === 'downloads' && <Downloads demo={demo} />}
        {state.pane === 'network' && <Network demo={demo} />}
        {state.pane === 'remote' && <Remote demo={demo} />}
        {state.pane === 'notifications' && <Notifications demo={demo} />}
        {state.pane === 'extensions' && <Extensions demo={demo} />}
        {state.pane === 'about' && <About />}
      </div>
    </div>
  )
}

type Settings = Demo['state']['settings']

/// A switch bound to one boolean setting.
function useToggle(demo: Demo) {
  return (key: { [K in keyof Settings]: Settings[K] extends boolean ? K : never }[keyof Settings]) => (
    <Switch on={demo.state.settings[key]} onChange={(on) => demo.setSetting(key, on)} />
  )
}

/// Up/down arrows for nudging a number, like the app's ChevronStepper.
function ChevronStepper({ up, down }: { up: () => void; down: () => void }) {
  const button = (d: string, action: () => void) => (
    <button onClick={action} className="flex h-2.75 w-4 items-center justify-center">
      <Glyph d={d} size={9} width={3} />
    </button>
  )
  return (
    <div className="flex flex-col overflow-hidden rounded-[5px] bg-ctl shadow-ctl">
      {button(ICON.up, up)}
      <div className="h-[.5px] bg-ctl-border" />
      {button(ICON.down, down)}
    </div>
  )
}

/// A text field with the same chrome as the other controls.
function Input({
  value,
  onChange,
  width,
  placeholder,
  type = 'text',
  numeric,
  mono,
  onBlur,
}: {
  value: string | number
  onChange: (value: string) => void
  width: number
  placeholder?: string
  type?: 'text' | 'password'
  numeric?: boolean
  mono?: boolean
  onBlur?: () => void
}) {
  return (
    <input
      type={type}
      value={value}
      placeholder={placeholder}
      spellCheck={false}
      autoComplete="off"
      inputMode={numeric ? 'numeric' : undefined}
      onChange={(e) => onChange(e.target.value)}
      onBlur={onBlur}
      style={{ width }}
      className={cx(
        'h-6 rounded-md border-0 bg-ctl px-1.75 shadow-ctl outline-none placeholder:text-text3',
        numeric && 'text-right tabular-nums',
        mono && 'font-mono text-xs',
      )}
    />
  )
}

/// Digits only, so a number field can't hold anything else.
const digits = (text: string) => Number(text.replace(/\D/g, '').slice(0, 5)) || 0

function General({ demo }: { demo: Demo }) {
  const { settings: s, now, checkingUntil } = demo.state
  const toggle = useToggle(demo)
  const checking = now < checkingUntil
  const setDays = (days: number) => demo.setSetting('removeAfterDays', Math.min(3650, Math.max(1, days)))
  const cleanup: [ListCleanup, string][] = [
    ['manually', 'Manually'],
    ['whenFinished', 'When Finished'],
    ['afterDays', s.removeAfterDays === 1 ? 'Day' : 'Days'],
  ]
  return (
    <>
      <Group>
        <Row title="Appearance">
          <Segmented<Appearance>
            options={[
              ['light', 'Light'],
              ['dark', 'Dark'],
              ['auto', 'Auto'],
            ]}
            value={s.appearance}
            onChange={(v) => demo.setSetting('appearance', v)}
            minWidth={56}
          />
        </Row>
        <Row title="Accent colour">
          <div className="flex gap-2">
            {(Object.keys(ACCENTS) as Accent[]).map((a) => (
              <button
                key={a}
                title={a}
                onClick={() => demo.setSetting('accent', a)}
                className="size-4 rounded-full"
                style={{
                  background: ACCENTS[a],
                  boxShadow:
                    s.accent === a
                      ? `0 0 0 2px var(--win), 0 0 0 3.5px ${ACCENTS[a]}`
                      : 'inset 0 0 0 .5px rgba(0,0,0,.2)',
                }}
              />
            ))}
          </div>
        </Row>
      </Group>
      <Group>
        <Row title="Show in menu bar" caption="Progress ring and live speed next to the clock.">
          {toggle('menuBar')}
        </Row>
        <Row title="Show progress on Dock icon">{toggle('dockProgress')}</Row>
        <Row title="Open at login">{toggle('launchAtLogin')}</Row>
      </Group>
      <Group>
        <Row
          title="Remove finished downloads from list"
          caption="Only clears the list. Files stay where they were saved."
        >
          <div className="flex items-center gap-2">
            {s.removeFinished === 'afterDays' && (
              <div className="flex items-center gap-1.5">
                <input
                  value={s.removeAfterDays}
                  inputMode="numeric"
                  onChange={(e) => setDays(digits(e.target.value))}
                  className="w-8.5 border-0 bg-transparent text-right tabular-nums outline-none"
                />
                <ChevronStepper up={() => setDays(s.removeAfterDays + 1)} down={() => setDays(s.removeAfterDays - 1)} />
              </div>
            )}
            <PopUp options={cleanup} value={s.removeFinished} onChange={(v) => demo.setSetting('removeFinished', v)} />
          </div>
        </Row>
        <Row
          title="Remove downloads whose file was deleted"
          caption="Also when the file is moved or renamed in Finder."
        >
          {toggle('removeDeleted')}
        </Row>
        <Row title="Ask before removing downloads">{toggle('confirmRemove')}</Row>
        <Row title="Ask before quitting while downloading" caption="Also while an archive is being extracted.">
          {toggle('confirmQuit')}
        </Row>
      </Group>
      <Group>
        <Row title="Check for updates automatically" caption="Once a day, from Haul's GitHub releases.">
          {toggle('checkForUpdates')}
        </Row>
        <Row title={`Version ${version}`}>
          <Pill
            small
            className="h-6"
            disabled={checking}
            onClick={() => demo.update(() => ({ checkingUntil: Date.now() + 1500 }))}
          >
            {checking ? 'Checking…' : 'Check Now'}
          </Pill>
        </Row>
      </Group>
    </>
  )
}

function Downloads({ demo }: { demo: Demo }) {
  const s = demo.state.settings
  const toggle = useToggle(demo)
  const setMax = (n: number) => demo.setSetting('maxConcurrent', Math.min(8, Math.max(1, n)))
  return (
    <>
      <Group>
        <Row title="Save downloads to">
          <PopUp
            options={[
              ['Downloads', 'Downloads'],
              ['other', 'Other…'],
              ['finder', 'Show in Finder'],
            ]}
            value="Downloads"
            onChange={() => {}}
            icon={<Glyph d={ICON.folder} size={14} className="text-accent" />}
          />
        </Row>
        <Row title="Sort into folders by kind" caption="Movies, Music, Pictures, Documents, Archives, Apps.">
          {toggle('autoSort')}
        </Row>
        <Row title="Compute SHA-256 checksums" caption="Shown in the inspector to compare with the publisher's.">
          {toggle('computeChecksum')}
        </Row>
        <Row title="Use the server's file date" caption="Files keep the date they last changed on the server.">
          {toggle('useServerDate')}
        </Row>
        <Row title="Record where files came from" caption="Shown as “Where from” in Finder's Get Info.">
          {toggle('recordSource')}
        </Row>
        <Row title="Skip web pages" caption="Links that open an HTML page instead of a file aren't saved.">
          {toggle('skipWebPages')}
        </Row>
      </Group>
      <Group>
        <Row title="Simultaneous downloads">
          <div className="flex items-center gap-2.5">
            <span className="min-w-3 text-right tabular-nums">{s.maxConcurrent}</span>
            <ChevronStepper up={() => setMax(s.maxConcurrent + 1)} down={() => setMax(s.maxConcurrent - 1)} />
          </div>
        </Row>
        <Row title="Connections per download">
          <Segmented
            options={[1, 4, 8, 16].map((n) => [n, String(n)] as [number, string])}
            value={s.connections}
            onChange={(v) => demo.setSetting('connections', v)}
            minWidth={34}
          />
        </Row>
        <Row
          title="Prevent sleep while downloading"
          caption="The display can still turn off. Closing the lid still sleeps."
        >
          {toggle('preventSleep')}
        </Row>
      </Group>
    </>
  )
}

function Network({ demo }: { demo: Demo }) {
  const s = demo.state.settings
  const toggle = useToggle(demo)
  return (
    <>
      <Group>
        <Row title="Limit download speed">{toggle('limitOn')}</Row>
        <div className={cx('flex items-center gap-3 px-3 py-2.5', !s.limitOn && 'opacity-40')}>
          <span className="text-xs text-text2">1 MB/s</span>
          <input
            type="range"
            min={1}
            max={50}
            value={s.limitMBps}
            onChange={(e) => demo.setSetting('limitMBps', Number(e.target.value))}
            className="flex-1 accent-accent"
          />
          <span className="min-w-14.5 text-right text-xs font-semibold tabular-nums">{s.limitMBps} MB/s</span>
        </div>
      </Group>
      <Group>
        <Row title="Only download on a schedule" caption="Queued downloads only start during these hours.">
          {toggle('scheduleOnly')}
        </Row>
        <div className={cx('flex items-center gap-2 px-3 py-2.5', !s.scheduleOnly && 'opacity-40')}>
          <span className="text-text2">From</span>
          <PopUp options={HOURS} value={s.scheduleFrom} onChange={(v) => demo.setSetting('scheduleFrom', v)} />
          <span className="text-text2">to</span>
          <PopUp options={HOURS} value={s.scheduleTo} onChange={(v) => demo.setSetting('scheduleTo', v)} />
        </div>
        <Row title="Pause on Personal Hotspot" caption="Also respects Low Data Mode.">
          {toggle('pauseOnExpensive')}
        </Row>
        <Row
          title="Multi-network downloads"
          caption={
            'Downloads go over Wi‑Fi, Ethernet and tethering at once. Not while a VPN or proxy is on.' +
            (s.pauseOnExpensive
              ? ' Metered networks, like a phone’s hotspot or tethering, are left out while Pause on Personal Hotspot is on.'
              : '')
          }
        >
          {toggle('useAllNetworks')}
        </Row>
      </Group>
      <Group>
        <Row
          title="Retry failed downloads"
          caption={`Up to ${MAX_RETRIES} times after a dropped connection or server error.`}
        >
          {toggle('autoRetry')}
        </Row>
      </Group>
      <Proxy demo={demo} />
    </>
  )
}

function Proxy({ demo }: { demo: Demo }) {
  const s = demo.state.settings
  const caption = {
    system: 'Follows System Settings → Network.',
    none: 'Connects directly, even when the system has a proxy set.',
    custom:
      s.proxyHost.trim() && s.proxyPort > 0
        ? 'Applies to downloads as they start or resume.'
        : "Enter a server and port. Until then, the system's proxy is used.",
  }[s.proxyMode]
  // Like AppSettings.proxyKind: follow the new kind's usual port unless one was typed in.
  const setKind = (kind: ProxyKind) =>
    demo.update((st) => ({
      settings: {
        ...st.settings,
        proxyKind: kind,
        proxyPort:
          st.settings.proxyPort === PROXY_PORT[st.settings.proxyKind] ? PROXY_PORT[kind] : st.settings.proxyPort,
      },
    }))
  return (
    <Group>
      <Row title="Proxy" caption={caption}>
        <PopUp<ProxyMode>
          options={[
            ['system', 'System'],
            ['none', 'None'],
            ['custom', 'Custom'],
          ]}
          value={s.proxyMode}
          onChange={(v) => demo.setSetting('proxyMode', v)}
        />
      </Row>
      {s.proxyMode === 'custom' && (
        <>
          <Row title="Type">
            <Segmented<ProxyKind>
              options={[
                ['http', 'HTTP'],
                ['socks', 'SOCKS5'],
              ]}
              value={s.proxyKind}
              onChange={setKind}
              minWidth={60}
            />
          </Row>
          <Row title="Server">
            <div className="flex items-center gap-1.5">
              <Input
                width={180}
                value={s.proxyHost}
                placeholder="proxy.example.com"
                onChange={(v) => demo.setSetting('proxyHost', v)}
              />
              <span className="text-text2">:</span>
              <Input
                width={56}
                numeric
                value={s.proxyPort || ''}
                onChange={(v) => demo.setSetting('proxyPort', digits(v))}
              />
            </div>
          </Row>
          <Row title="Username" caption="Optional. The password is kept in the Keychain.">
            <Input
              width={180}
              value={s.proxyUser}
              placeholder="None"
              onChange={(v) => demo.setSetting('proxyUser', v)}
            />
          </Row>
          <Row title="Password">
            <Input
              width={180}
              type="password"
              value={s.proxyPassword}
              onChange={(v) => demo.setSetting('proxyPassword', v)}
            />
          </Row>
          <Row
            title="Don't use the proxy for"
            caption="Separate hosts with commas. A domain covers its subdomains too."
          >
            <Input
              width={180}
              value={s.proxyBypass}
              placeholder="localhost, example.com"
              onChange={(v) => demo.setSetting('proxyBypass', v)}
            />
          </Row>
        </>
      )}
    </Group>
  )
}

/// The remote downloads page and API, like RemoteSettings. Nothing is served from the demo.
function Remote({ demo }: { demo: Demo }) {
  const s = demo.state.settings
  const toggle = useToggle(demo)
  const portOK = s.remotePort >= 1 && s.remotePort <= 65535
  const page = `http://localhost:${s.remotePort}/`
  const network = `http://192.168.1.24:${s.remotePort}/`
  const copy = (text: string) => navigator.clipboard?.writeText(text).catch(() => {})
  return (
    <>
      <Group>
        <Row title="Add downloads remotely" caption="A page to paste links into, and an API for curl and scripts.">
          {toggle('remoteOn')}
        </Row>
        {s.remoteOn && (
          <>
            <Row
              title="Available to"
              caption={
                s.remoteScope === 'thisMac'
                  ? 'Only this Mac, and a tunnel running on it.'
                  : 'Devices on your network, and a tunnel on another machine.'
              }
            >
              <PopUp<RemoteScope>
                options={[
                  ['thisMac', 'This Mac'],
                  ['network', 'Network'],
                ]}
                value={s.remoteScope}
                onChange={(v) => demo.setSetting('remoteScope', v)}
              />
            </Row>
            <Row title="Port">
              <Input
                width={64}
                numeric
                value={s.remotePort || ''}
                onChange={(v) => demo.setSetting('remotePort', digits(v))}
              />
            </Row>
            <Row title="Password" caption="Needed to use the page and the API. Kept in the Keychain.">
              <div className="flex items-center gap-1.5">
                <Input
                  width={160}
                  mono
                  value={s.remotePassword}
                  onChange={(v) => demo.setSetting('remotePassword', v)}
                  // Never left empty, like RemoteSettings.savePassword.
                  onBlur={() => !s.remotePassword.trim() && demo.setSetting('remotePassword', newPassword())}
                />
                <Pill small className="h-6" onClick={() => demo.setSetting('remotePassword', newPassword())}>
                  New
                </Pill>
              </div>
            </Row>
          </>
        )}
      </Group>
      {s.remoteOn && (
        <>
          <Group>
            {portOK ? (
              <Row
                title={s.remoteScope === 'thisMac' ? 'Running on this Mac' : 'Running on your network'}
                caption={page}
              >
                <div className="flex gap-1.5">
                  <Pill small className="h-6">
                    Open
                  </Pill>
                  <Pill
                    small
                    className="h-6"
                    onClick={() => copy(`curl -u ':${s.remotePassword}' -d 'https://example.com/file.zip' ${page}add`)}
                  >
                    Copy curl
                  </Pill>
                </div>
              </Row>
            ) : (
              <Row title="Couldn't start" caption="Choose a port from 1 to 65535." />
            )}
            {portOK && s.remoteScope === 'network' && (
              <Row title="On other devices" caption={network}>
                <Pill small className="h-6" onClick={() => copy(network)}>
                  Copy
                </Pill>
              </Row>
            )}
          </Group>
          <div className="px-3 text-xs text-text2">
            Downloads added remotely start right away in the default folder. To add them from anywhere, point a tunnel
            such as cloudflared or Tailscale at the page.
          </div>
          <div className="px-3 text-[11px] text-text2">
            <Glyph d={ICON.warning} size={12} width={2.2} className="mr-1 inline-block align-[-2px] text-orange" />
            On the internet, anyone with the link can try to guess the password and add downloads to this Mac. Use a
            long password, and prefer a private tunnel such as Tailscale, or one behind a sign-in such as Cloudflare
            Access.
          </div>
        </>
      )}
    </>
  )
}

function Notifications({ demo }: { demo: Demo }) {
  const toggle = useToggle(demo)
  return (
    <>
      <Group>
        <Row title="Download added">{toggle('notifyAdded')}</Row>
        <Row title="Download finished">{toggle('notify')}</Row>
        <Row title="Download failed" caption="After any automatic retries have run out.">
          {toggle('notifyFailed')}
        </Row>
      </Group>
      <Group>
        <Row title="Only when Haul isn't in front">{toggle('notifyOnlyInBackground')}</Row>
      </Group>
    </>
  )
}

/// A browser's icon and name, and its control, like the app's BrowserRow. The app shows each
/// installed browser; the demo shows Safari and the two stores the extension comes from.
function BrowserRow({
  name,
  color,
  caption,
  children,
}: {
  name: string
  color: string
  caption?: string
  children: ReactNode
}) {
  return (
    <div className="flex items-center gap-2.5 px-3 py-2">
      <div
        className="flex size-7 flex-none items-center justify-center rounded-full text-[13px] font-bold text-white"
        style={{ background: color }}
      >
        {name[0]}
      </div>
      <div className="flex-1">
        <div>{name}</div>
        {caption && <div className="mt-0.5 text-[11px] text-text2">{caption}</div>}
      </div>
      {children}
    </div>
  )
}

function Extensions({ demo }: { demo: Demo }) {
  const on = demo.state.safariOn
  const store = (name: string, color: string, href: string) => (
    <BrowserRow name={name} color={color}>
      <a
        href={href}
        target="_blank"
        rel="noreferrer"
        className="inline-flex h-6 items-center rounded-[13px] bg-ctl px-3 text-xs text-text! shadow-ctl"
      >
        Add to {name.split(' ').pop()}
      </a>
    </BrowserRow>
  )
  return (
    <div className="flex flex-col gap-2.5">
      <div className="px-3 text-xs text-text2">
        Haul's extension adds “Download with Haul” to the menu for links. In browsers other than Safari, it also sends
        the downloads you start to Haul.
      </div>
      <Group>
        <BrowserRow name="Safari" color="#1a8cff" caption={on ? 'Turned on' : 'Turned off'}>
          <Pill small className="h-6" onClick={() => demo.update(() => ({ safariOn: true }))}>
            {on ? 'Safari Settings…' : 'Turn On in Safari…'}
          </Pill>
        </BrowserRow>
        {store('Google Chrome', '#e8453c', links.chromeExtension)}
        {store('Firefox', '#ff7139', links.firefoxExtension)}
      </Group>
    </div>
  )
}

function About() {
  return (
    <div className="flex flex-col items-center pt-3 text-center">
      <AppTile size={96} radius={22} glyph={56} />
      <div className="mt-2 text-xl font-semibold">Haul</div>
      <div className="mt-0.5 text-xs text-text2 select-text">Version {version}</div>
      <div className="mt-4.5 text-xs text-text2">Haul is free and open source. Sponsoring helps keep it that way.</div>
      <a
        href={links.sponsor}
        target="_blank"
        rel="noreferrer"
        className="mt-3 inline-flex h-7 items-center rounded-[14px] bg-accent px-4 font-medium text-white!"
      >
        ♥ Sponsor Haul
      </a>
    </div>
  )
}
