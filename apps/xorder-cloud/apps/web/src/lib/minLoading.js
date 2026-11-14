// Keep a loading state on screen for at least `ms` so skeleton shimmers are
// actually perceived — API responses (especially on localhost) are often near
// instant, which would flash the skeleton for a few milliseconds and look like
// nothing happened. Resolves with the awaited value.
export async function withMinDuration(promise, ms = 450) {
    const [result] = await Promise.all([promise, new Promise((r) => setTimeout(r, ms))])
    return result
}
