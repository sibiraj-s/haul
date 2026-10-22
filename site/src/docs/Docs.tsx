import { useEffect, useState } from 'react'
import { Footer } from '../components/Footer'
import { Header } from '../components/Header'
import { sections } from './sections'

export function Docs() {
  const [current, setCurrent] = useState(sections[0].id)

  useEffect(() => {
    // The page renders after load, so the browser can't scroll to a #fragment by itself.
    const target = location.hash ? document.getElementById(decodeURIComponent(location.hash.slice(1))) : null
    target?.scrollIntoView()

    // Highlight the section at the top of the view in the sidebar.
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)
        if (visible[0]) setCurrent(visible[0].target.id)
      },
      { rootMargin: '-64px 0px -70% 0px' },
    )
    for (const s of sections) {
      const el = document.getElementById(s.id)
      if (el) observer.observe(el)
    }
    return () => observer.disconnect()
  }, [])

  return (
    <div className="min-h-screen bg-bg font-sans text-text">
      <Header home="../" />
      <div className="mx-auto flex max-w-270 gap-12 px-6 pt-12">
        <nav className="sticky top-25 hidden w-48 shrink-0 self-start md:block" aria-label="Sections">
          <ul className="flex flex-col gap-0.5 text-sm">
            {sections.map((s) => (
              <li key={s.id}>
                <a
                  href={`#${s.id}`}
                  aria-current={current === s.id ? 'true' : undefined}
                  className="block rounded-md px-2.5 py-1.5 text-text2 hover:text-text aria-current:bg-bg2 aria-current:font-medium aria-current:text-text"
                >
                  {s.title}
                </a>
              </li>
            ))}
          </ul>
        </nav>
        <main className="min-w-0 flex-1">
          <h1 className="font-display text-[clamp(32px,5vw,44px)] leading-[1.1] font-bold tracking-[-.03em]">
            Haul Docs
          </h1>
          <p className="mt-3 text-[17px] text-text2">How to get links into Haul, and what each setting does.</p>
          {/* On narrow screens the sidebar is hidden, so list the sections here instead. */}
          <ul className="mt-6 flex flex-wrap gap-2 md:hidden">
            {sections.map((s) => (
              <li key={s.id}>
                <a
                  href={`#${s.id}`}
                  className="block rounded-full bg-bg2 px-3 py-1 text-[13px] text-text2 hover:text-text"
                >
                  {s.title}
                </a>
              </li>
            ))}
          </ul>
          {sections.map((s) => (
            <section key={s.id} id={s.id} className="border-t-[.5px] border-sep pt-10 mt-10 first-of-type:border-0">
              <h2 className="font-display text-[26px] leading-tight font-bold tracking-[-.02em]">{s.title}</h2>
              <div className="mt-4 flex flex-col gap-4 text-[15px] leading-relaxed text-pretty">{s.body}</div>
            </section>
          ))}
        </main>
      </div>
      <Footer home="../" />
    </div>
  )
}
