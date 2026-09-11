# Evidence-driven agent workflow

Use the repository and nearest `AGENTS.md` as the source of truth. Keep the
smallest relevant context in the prompt and treat delegated output as evidence
that requires coordinator review.

## Roles

- `build`, `plan`, `explore`, `worker`, and `review` use MiniMax M2.7.
- `worker-m3` is the manual hard fallback for difficult implementation.
- `expert` uses GPT-5.6 Luna for architecture, hard debugging, and arbitration.
- `web-verifier`, `android-verifier`, and `ui-specialist` are capability-scoped.
- `ask` is read-only and answers from the smallest repository surface.

Delegate only a bounded task that materially improves speed, expertise, or
independent verification. Prefer one child; use two only for genuinely
independent work. Return exact paths, observed checks, and uncertainty.

Verify with the cheapest authoritative check first, then escalate to focused
integration, browser, Android, or physical-device evidence only when the
changed surface requires it. Never claim an unobserved result. Preserve
unrelated work and do not commit, push, use SSH, or alter credentials unless
the user explicitly requests it.
