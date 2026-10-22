import type { ReactNode } from 'react'
import { links } from '../links'

const H3 = ({ children }: { children: ReactNode }) => <h3 className="mt-3 text-[17px] font-semibold">{children}</h3>
const P = ({ children }: { children: ReactNode }) => <p className="text-text2">{children}</p>
const Ui = ({ children }: { children: ReactNode }) => <strong className="font-semibold text-text">{children}</strong>
const Code = ({ children }: { children: ReactNode }) => (
  <code className="rounded bg-bg2 px-1.5 py-0.5 font-mono text-[13px] text-text">{children}</code>
)
const Pre = ({ children }: { children: string }) => (
  <pre className="overflow-x-auto rounded-xl bg-bg2 px-4 py-3 font-mono text-[13px] leading-relaxed text-text">
    {children}
  </pre>
)
const Ul = ({ children }: { children: ReactNode }) => (
  <ul className="flex list-disc flex-col gap-1.5 pl-5 text-text2 marker:text-text3">{children}</ul>
)
const Ol = ({ children }: { children: ReactNode }) => (
  <ol className="flex list-decimal flex-col gap-1.5 pl-5 text-text2 marker:text-text3">{children}</ol>
)
const A = ({ href, children }: { href: string; children: ReactNode }) => (
  <a href={href} target="_blank" rel="noreferrer" className="text-accent hover:underline">
    {children}
  </a>
)

/** Rows of a two-column table: what to press or set, and what it does. */
function Table({ rows }: { rows: [ReactNode, ReactNode][] }) {
  return (
    <div className="overflow-hidden rounded-xl border-[.5px] border-sep">
      <table className="w-full text-left text-[14px]">
        <tbody>
          {rows.map(([a, b], i) => (
            <tr key={i} className="border-t-[.5px] border-sep first:border-0">
              <td className="w-2/5 bg-bg2 px-4 py-2.5 align-top font-medium">{a}</td>
              <td className="px-4 py-2.5 align-top text-text2">{b}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

const shortcuts: [string, [string, string][]][] = [
  [
    'General',
    [
      ['⌘N', 'Add Download'],
      ['⌘F', 'Search'],
      ['⌘,', 'Settings'],
      ['⌘0', 'Show Main Window'],
    ],
  ],
  [
    'Selected Download',
    [
      ['↑ ↓', 'Select Previous or Next'],
      ['Space', 'Pause, Resume or Start'],
      ['Return', 'Rename'],
      ['⌘O', 'Open'],
      ['⌘R', 'Show in Finder'],
      ['⇧⌘C', 'Copy Link'],
      ['⌘⌫', 'Remove'],
    ],
  ],
  [
    'All Downloads',
    [
      ['⌥⌘P', 'Pause All'],
      ['⌥⌘R', 'Resume All'],
      ['⇧⌘⌫', 'Clear Completed'],
    ],
  ],
  [
    'View',
    [
      ['⌘1 – ⌘5', 'All, Active, Queued, Completed, Failed'],
      ['⌃⌘S', 'Show or Hide Sidebar'],
      ['⌥⌘I', 'Show or Hide Inspector'],
    ],
  ],
]

export const sections: { id: string; title: string; body: ReactNode }[] = [
  {
    id: 'install',
    title: 'Install',
    body: (
      <>
        <P>Haul needs macOS 26 or later on a Mac with Apple Silicon.</P>
        <Ol>
          <li>
            Download <Code>Haul-&lt;version&gt;.dmg</Code> from the <A href={links.latestRelease}>latest release</A>.
          </li>
          <li>Open it and drag Haul to Applications.</li>
          <li>Open Haul from Applications.</li>
        </Ol>
        <H3>Updates</H3>
        <P>
          Haul checks its GitHub releases for updates once a day and installs them from within the app. Turn this off in{' '}
          <Ui>Settings → General</Ui>, or check yourself with <Ui>Haul → Check for Updates…</Ui>
        </P>
      </>
    ),
  },
  {
    id: 'adding',
    title: 'Adding downloads',
    body: (
      <>
        <P>
          Choose <Ui>File → Add Download…</Ui> (⌘N) and paste a link. Paste several links, or text that contains them,
          to add them all at once. Haul checks each link first and shows the file's name and size.
        </P>
        <P>Before adding, the panel lets you choose:</P>
        <Ul>
          <li>Where to save the file.</li>
          <li>
            What to do when it finishes: <Ui>Do Nothing</Ui>, <Ui>Open</Ui> or <Ui>Show in Finder</Ui>.
          </li>
          <li>
            <Ui>Extract when finished</Ui>, for zip, tar (.tar.gz, .tar.bz2, .tar.xz, .tgz…) and 7z archives. The
            archive is kept next to what it extracts.
          </li>
          <li>
            <Ui>Start immediately</Ui>, or add it to the end of the queue.
          </li>
        </Ul>
        <P>
          Links from other apps, the browser extension and the <Code>haul</Code> command all open this panel with the
          links filled in. Nothing downloads until you confirm it there.
        </P>
      </>
    ),
  },
  {
    id: 'safari',
    title: 'Safari extension',
    body: (
      <>
        <P>
          The extension adds <Ui>Download with Haul</Ui> to the menu you get by Control-clicking a link, and{' '}
          <Ui>Download Links with Haul</Ui> for selected text.
        </P>
        <Ol>
          <li>
            Open <Ui>Haul → Settings → General</Ui> and click <Ui>Turn On in Safari…</Ui>, or go to{' '}
            <Ui>Safari → Settings → Extensions</Ui>.
          </li>
          <li>Turn on Haul.</li>
          <li>
            To download files that need you to be signed in, allow the extension on those sites. Haul then sends
            Safari's cookies for the site, its User-Agent and the page as the Referer, so the download works as it would
            in Safari.
          </li>
        </Ol>
        <P>Links from private windows are sent without cookies.</P>
      </>
    ),
  },
  {
    id: 'chrome-firefox',
    title: 'Chrome and Firefox extension',
    body: (
      <>
        <P>
          The extension hands downloads you start in Chrome, Firefox, Brave, Edge, Vivaldi or Arc to Haul, which opens
          them in the Add panel instead of the browser downloading them. It also adds <Ui>Download with Haul</Ui> to the
          menu for links and <Ui>Download Links with Haul</Ui> for selected text.
        </P>
        <Ol>
          <li>Open Haul once, so it can tell your browsers where to find it.</li>
          <li>
            Install it from the <A href={links.chromeExtension}>Chrome Web Store</A> (also for Brave, Edge, Vivaldi and
            Arc) or from <A href={links.firefoxExtension}>Firefox Add-ons</A>.
          </li>
          <li>
            In Firefox, allow the extension on all sites in <Ui>Add-ons → Haul → Permissions</Ui>, so it can take
            downloads before Firefox asks what to do with them and send the site's cookies.
          </li>
        </Ol>
        <P>
          Click the Haul button in the toolbar to stop or start capturing downloads; it shows <Ui>off</Ui> while it
          isn't. If Haul can't be reached, the browser downloads the file as usual. Like the Safari extension, it sends
          the site's cookies, the browser's User-Agent and the page as the Referer, and nothing from private windows.
        </P>
      </>
    ),
  },
  {
    id: 'other-apps',
    title: 'From other apps',
    body: (
      <>
        <H3>Share menu</H3>
        <P>
          Haul appears in the Share menu for web links. If it isn't listed, choose <Ui>Edit Extensions…</Ui> at the
          bottom of the Share menu and turn it on.
        </P>
        <H3>Services</H3>
        <P>
          Select a link, or text containing links, in any app and choose <Ui>Services → Download with Haul</Ui> from the
          app menu or the Control-click menu.
        </P>
        <H3>haul:// links</H3>
        <P>
          Open a <Code>haul://add</Code> URL with one percent-encoded <Code>url</Code> item for each link:
        </P>
        <Pre>{'open "haul://add?url=https%3A%2F%2Fexample.com%2Ffile.zip"'}</Pre>
      </>
    ),
  },
  {
    id: 'command-line',
    title: 'Command line',
    body: (
      <>
        <P>
          Choose <Ui>Haul → Install Command Line Tool…</Ui> to add a symlink to the <Code>haul</Code> command at{' '}
          <Code>~/.local/bin/haul</Code>. It needs no password.
        </P>
        <P>
          If your shell doesn't search <Code>~/.local/bin</Code> yet, Haul shows the line to add to your shell's startup
          file and can add it for you to <Code>~/.zshrc</Code>, <Code>~/.bash_profile</Code> or fish's{' '}
          <Code>config.fish</Code>. Open a new Terminal window afterwards.
        </P>
        <Pre>{`haul add https://example.com/file.zip https://example.com/other.iso
haul add < links.txt
haul --version`}</Pre>
        <P>
          With no links given, <Code>haul add</Code> reads them from standard input, separated by spaces or new lines.
        </P>
        <P>
          The symlink points into Haul.app, so updating Haul updates the command too. If you move Haul, it fixes the
          link the next time it opens. <Ui>Haul → Uninstall Command Line Tool…</Ui> removes the symlink and leaves your
          shell's startup files as they are.
        </P>
      </>
    ),
  },
  {
    id: 'managing',
    title: 'Managing downloads',
    body: (
      <>
        <P>
          Control-click a download, or use the <Ui>Downloads</Ui> menu, for what you can do with it. The inspector (⌥⌘I)
          shows its details, including the SHA-256 checksum when that's turned on.
        </P>
        <Table
          rows={[
            ['Pause, Resume', 'Stops and continues where it left off, also after quitting Haul.'],
            ['Start Now, Start Next', 'Starts a queued download now, or makes it the next one to start.'],
            ['Move to End of Queue', 'Lets the other queued downloads go first.'],
            ['Retry', 'Tries a failed download again. Haul already retries dropped connections automatically.'],
            ['Sign In…', 'For servers that ask for a username and password.'],
            [
              'Update Link…',
              'Swaps in a fresh link when the old one has expired. If it serves the same file, the download keeps its progress.',
            ],
            ['Restart from Beginning', 'Throws away what was downloaded and starts again.'],
            ['Remove…, Clear Completed…', 'Takes downloads off the list. Finished files stay where they were saved.'],
          ]}
        />
      </>
    ),
  },
  {
    id: 'settings',
    title: 'Settings',
    body: (
      <>
        <H3>General</H3>
        <P>
          Appearance and accent colour, progress in the menu bar and on the Dock icon, opening at login, when finished
          downloads leave the list, the Safari extension, and automatic updates.
        </P>
        <H3>Downloads</H3>
        <Table
          rows={[
            ['Save downloads to', 'The default folder. Each download can still go somewhere else.'],
            [
              'Sort into folders by kind',
              'Movies, Music, Pictures, Documents, Archives and Apps get their own folders.',
            ],
            ['Compute SHA-256 checksums', "Shown in the inspector, to compare with the publisher's."],
            ["Use the server's file date", 'Files keep the date they last changed on the server.'],
            ['Record where files came from', "Shown as “Where from” in Finder's Get Info."],
            ['Skip web pages', "Links that open an HTML page instead of a file aren't saved."],
            ['Simultaneous downloads', 'How many run at once. The rest wait in the queue.'],
            ['Connections per download', 'Large files are split across this many connections.'],
            ['Prevent sleep while downloading', 'The display can still turn off. Closing the lid still sleeps.'],
          ]}
        />
        <H3>Network</H3>
        <Table
          rows={[
            ['Limit download speed', 'A cap shared by all downloads.'],
            [
              'Only download on a schedule',
              'Queued downloads start only between the hours you set, such as overnight.',
            ],
            [
              'Pause on Personal Hotspot',
              'Downloads wait while on Personal Hotspot or Low Data Mode. Click the badge in the toolbar to download anyway.',
            ],
            ['Retry failed downloads', 'Retries a few times after a dropped connection or server error.'],
            [
              'Proxy',
              <>
                <Ui>System</Ui> follows System Settings → Network, <Ui>None</Ui> connects directly, and <Ui>Custom</Ui>{' '}
                uses an HTTP or SOCKS5 proxy, with an optional sign-in kept in the Keychain and a list of hosts that
                skip it.
              </>,
            ],
          ]}
        />
        <H3>Notifications</H3>
        <P>
          Notify when a download is added, finishes or fails (after any automatic retries), optionally only when Haul
          isn't in front.
        </P>
      </>
    ),
  },
  {
    id: 'shortcuts',
    title: 'Keyboard shortcuts',
    body: (
      <>
        <P>
          Also in the app under <Ui>Help → Keyboard Shortcuts</Ui> (⌘/).
        </P>
        {shortcuts.map(([group, rows]) => (
          <div key={group} className="flex flex-col gap-2">
            <H3>{group}</H3>
            <Table rows={rows.map(([keys, action]) => [<kbd className="font-sans">{keys}</kbd>, action])} />
          </div>
        ))}
      </>
    ),
  },
  {
    id: 'help',
    title: 'Getting help',
    body: (
      <P>
        Found a bug or missing something? <A href={links.issues}>Open an issue</A> on GitHub. The{' '}
        <A href={links.releases}>release notes</A> list what changed in each version.
      </P>
    ),
  },
]
