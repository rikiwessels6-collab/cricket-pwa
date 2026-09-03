# Rain Calc — Cricket Umpire Weather Calculator

A Progressive Web App that helps cricket umpires work out overs remaining,
overs lost, and an approximate revised par score when weather interrupts a
match. Installable and fully usable offline, since grounds often have poor
signal.

## Features

- **Match setup** — overs per innings, overs-per-hour rate, minimum overs
  for a result, and a rounding rule, all configurable to match your
  league's own playing conditions.
- **Competition presets** — pick a competition (e.g. Marsh One Day Cup
  2026-27) to auto-fill its official numbers, with a link to the source
  playing conditions PDF and a citation of the exact clauses. A Final
  toggle switches the minimum-overs threshold where the competition's
  rules differ for Finals. See `src/lib/competitionPresets.ts`.
- **Interruption log** — start/stop a live stoppage timer, or add a past
  stoppage manually, per innings. Multiple interruptions per innings are
  supported.
- **Overs remaining** — automatically recalculates each innings' available
  overs using the standard proportional formula: overs lost = (minutes
  lost ÷ 60) × overs-per-hour, rounded per your league's rule. Flags when
  an innings drops below the minimum-overs threshold or is washed out.
- **Par score estimate** — an approximate, resource-based target/par score
  for the team batting second. **This is not the official ICC
  Duckworth-Lewis-Stern (DLS) calculation** — the real DLS tables are
  proprietary and not publicly reproducible. This app's model is an
  original approximation intended as a rough guide only; use an official
  DLS-certified tool for match results that require one.
- **Offline-first** — installable as a PWA with a service worker that
  precaches the app shell, and match data is stored on-device
  (`localStorage`) so it survives reloads with no network connection.

## Development

```bash
npm install
npm run dev       # start the dev server
npm run test      # run the calculation-logic unit tests
npm run build     # typecheck + production build (also generates the service worker)
npm run preview   # serve the production build locally
```

## Project layout

- `src/lib/oversCalculator.ts` — overs-lost / overs-remaining formula.
- `src/lib/parScore.ts` — resource-based par score estimator.
- `src/hooks/useMatchState.ts` — match state, persisted to `localStorage`.
- `src/components/` — Match setup, interruption log, overs summary, and
  par score UI.
