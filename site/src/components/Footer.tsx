import { links } from '../links'

export function Footer() {
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
    </footer>
  )
}
