# Lift & Log — Calories and Workouts

An installable, offline-first Progressive Web App for iPhone that tracks daily
calories and strength workouts. Your weights go up automatically as you get stronger.

## Features

- **Food** — log foods with kcal and optional protein/carbs/fat, grouped by meal.
  Includes a calorie ring, a protein goal bar, servings, and "My Foods" for one-tap re-logging.
- **Train** — workout templates (two starters, Upper A and Lower A, which you can edit or delete).
  Each exercise has sets, a rep range, a starting weight and an increment.
  Starting a workout fills in today's suggested weights. You tick off sets as you go,
  and a rest timer starts after each set.
- **Automatic progression** (double progression, `src/lib/progression.ts`):
  - first time → the starting weight
  - max reps hit on every set → next session adds the increment
  - all sets inside the rep range → same weight, chase more reps
  - missed min reps once → retry the same weight
  - missed twice in a row at the same weight → deload ~10% (rounded to the increment)

  Exercises are matched by name across workouts, so "Bench Press" shares one history.
- **Progress** — working weight and estimated 1-rep max chart for each exercise,
  14-day calories vs goal, and a body-weight log.
- **Settings** — goals, kg/lb, rest timer, JSON backup export/import (uses the iOS share sheet).

All data stays on the device (`localStorage`). Export a backup now and then.

## Install on iPhone

Deploy `dist/` to any HTTPS host (GitHub Pages, Netlify, Vercel…). Open it in Safari,
tap **Share → Add to Home Screen**.

## Development

```bash
npm install
npm run dev     # dev server
npm test        # progression + nutrition unit tests
npm run build   # typecheck + production build with service worker
npm run icons   # regenerate PNG icons from scripts/icon-source.svg
```
