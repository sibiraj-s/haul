import { links } from '../links'
import { useLatestRelease } from '../useLatestRelease'
import { DownloadIcon } from './Icons'

/** The stores' own badges, used unmodified apart from size as their branding guidelines require. */
function StoreBadge({ href, src, alt }: { href: string; src: string; alt: string }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className="rounded-lg outline-offset-4 hover:opacity-85">
      <img src={src} alt={alt} className="h-11 w-auto" />
    </a>
  )
}

export function Hero() {
  const { version, downloadURL } = useLatestRelease()

  return (
    <section id="top" className="mx-auto flex max-w-270 flex-col items-center px-6 pt-18 text-center">
      {/* The app's own icon, exported from the built app: glass on a gradient, with the margin and
          shadow macOS gives it, so it reads as the app rather than another download button. */}
      <img src="./app-icon.png" alt="" width={128} height={128} className="size-28" />
      <h1 className="mt-4 font-display text-[clamp(40px,7vw,72px)] leading-[1.04] font-bold tracking-[-.035em] text-balance">
        Downloads, handled.
      </h1>
      <p className="mt-3 max-w-140 text-[clamp(17px,2vw,21px)] leading-[1.45] text-pretty text-text2">
        Haul is a download manager built for macOS.
      </p>
      <div className="mt-8 flex flex-col items-center gap-3">
        {/* The header's Download link targets this button; the scroll margin stops it mid-screen
            instead of tucked under the sticky header, with the demo filling the view. */}
        <a
          id="download"
          href={downloadURL}
          className="flex h-11.5 scroll-mt-[40vh] outline-offset-4 items-center gap-2 rounded-full bg-text px-6.5 text-base font-semibold text-bg hover:opacity-85"
        >
          <DownloadIcon className="size-4.5 stroke-bg stroke-[2.2]" />
          Download for Mac
        </a>
        <span className="text-[13px] text-text2">
          Free and open source · Version {version} · macOS 26 or later · Apple Silicon
        </span>
      </div>
      <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
        <StoreBadge href={links.chromeExtension} src="./chrome-web-store.png" alt="Available in the Chrome Web Store" />
        <StoreBadge href={links.firefoxExtension} src="./firefox-add-ons.svg" alt="Get the add-on for Firefox" />
      </div>
    </section>
  )
}
