# Architecture

## Decisions

| Decision | Why |
|---|---|
| One app, one person per iPhone | Each partner installs it on their own phone. No profile switching, no shared data. |
| No account or server; Face ID / passcode lock | Health data never leaves the phone, so a login would add a server and privacy surface with no feature needing it. LocalAuthentication only reports success; the app never sees face data. |
| SwiftData store with iOS file protection | Encrypted at rest while the phone is locked (`completeUnlessOpen`). Exportable as JSON and erasable in Settings. |
| Programs imported from the coach's workbooks | `tools/importer` turns the untouched `.xlsx` files into bundled JSON plus a review report; every judgement call is in `coach_decisions.json`. |
| Logic in `SteadyCore` | Pure Swift with no UI, tested on its own. The swap rules are ported from the Python reference and tested to give the same answers. |
| XcodeGen | The project is a readable `project.yml` instead of a generated `.pbxproj`, so changes review cleanly. |
| Swift 5 language mode | Avoids strict-concurrency churn while the app is small; revisit for Swift 6. |

## Phases

1. **Done here:** project, data models, bundled content, Face ID lock and privacy shield, onboarding (health notice, consents, lock, profile, goals, experience, equipment, schedule and fixed activities, program choice, starting strengths, check-in, food targets), Today, program preview with exercise sheets and equipment swaps, Settings (equipment, lock, privacy policy, export, erase).
2. Workout logging, progressive overload, supersets, rest timer, swaps and session versions in a workout, video sheet and "Add my video".
3. Scheduling: rotation, missed sessions, days off, calendar sync.
4. Apple Health, steps, runs, Strava.
5. Nutrition: barcode scanner, food log, adaptive targets, macro timing.
6. Weekly check-in, measurements, photos, weight trend, summaries, notifications.
7. Polish, accessibility pass, App Store / TestFlight readiness.
