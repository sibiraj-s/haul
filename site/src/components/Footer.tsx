import { links } from '../links'

/** `home` is the landing page relative to the current one: empty on it, "../" from other pages. */
export function Footer({ home = '' }: { home?: string }) {
  return (
    <footer className="mx-auto flex max-w-270 flex-wrap items-center gap-x-6 gap-y-3 px-6 pt-18 pb-10 text-[13px] text-text2">
      <span className="min-w-40 flex-1">© {new Date().getFullYear()} Haul</span>
      <a href={links.releases} target="_blank" rel="noreferrer" className="hover:underline">
        Release notes
      </a>
      <a href={links.repo} target="_blank" rel="noreferrer" className="hover:underline">
        Source code
      </a>
      <a href={links.issues} target="_blank" rel="noreferrer" className="hover:underline">
        Report an issue
      </a>
      <a href={`${home}privacy/`} className="hover:underline">
        Privacy
      </a>
      <a href={`${home}terms/`} className="hover:underline">
        Terms
      </a>
    </footer>
  )
}
