import { links } from '../links'
import { DownloadIcon } from './Icons'

/** `home` is the landing page relative to the current one: empty on it, "../" from the docs. */
export function Header({ home = '' }: { home?: string }) {
  return (
    <header className="sticky top-0 z-10 border-b-[.5px] border-sep bg-bg/80 backdrop-blur-xl backdrop-saturate-[1.8]">
      <div className="mx-auto flex h-13 max-w-270 items-center justify-between gap-6 px-6">
        <a href={home || '#top'} className="flex items-center gap-2 text-base font-bold text-text">
          <span className="flex size-6 items-center justify-center rounded-md bg-accent shadow-[inset_0_1px_0_rgba(255,255,255,.35)]">
            <DownloadIcon className="size-3.75 stroke-white stroke-[2.6]" />
          </span>
          Haul
        </a>
        <nav className="hidden flex-1 gap-5 text-sm sm:flex">
          <a href={`${home}#features`} className="text-text2 hover:text-text">
            Features
          </a>
          <a href={`${home}docs/`} className="text-text2 hover:text-text">
            Docs
          </a>
          <a href={`${home}#sponsor`} className="text-text2 hover:text-text">
            Sponsor
          </a>
          <a href={links.repo} target="_blank" rel="noreferrer" className="text-text2 hover:text-text">
            GitHub
          </a>
        </nav>
        <a
          href={home ? links.latestRelease : '#download'}
          target={home ? '_blank' : undefined}
          rel={home ? 'noreferrer' : undefined}
          // Following the link scrolls to the button; also move focus there, so Return downloads.
          onClick={() =>
            requestAnimationFrame(() => document.getElementById('download')?.focus({ preventScroll: true }))
          }
          className="flex h-7.5 items-center rounded-full bg-text px-3.5 text-[13px] font-semibold text-bg hover:opacity-85"
        >
          Download
        </a>
      </div>
    </header>
  )
}
