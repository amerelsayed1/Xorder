// v-reveal: fade-and-rise an element the first time it scrolls into view.
//
//   <div v-reveal>            — reveal with no delay
//   <div v-reveal="0.08">     — stagger: delay in seconds
//
// Elements start visible; the hidden starting state is only applied once JS
// has run (html.lp-reveal), so content never disappears if the script fails,
// and users who ask for reduced motion skip the effect entirely.

const reduced = () =>
    typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

let io = null
function observer() {
    if (io) return io
    io = new IntersectionObserver(
        (entries) => {
            entries.forEach((e) => {
                if (!e.isIntersecting) return
                e.target.classList.add('is-in')
                io.unobserve(e.target)
            })
        },
        { threshold: 0.12, rootMargin: '0px 0px -40px 0px' },
    )
    return io
}

export const vReveal = {
    mounted(el, binding) {
        if (reduced() || typeof IntersectionObserver === 'undefined') return
        document.documentElement.classList.add('lp-reveal')
        el.classList.add('lp-rv')
        const d = Number(binding.value)
        if (d) el.style.setProperty('--rv-d', `${d}s`)
        observer().observe(el)
    },
    unmounted(el) {
        io?.unobserve(el)
    },
}
