# Steady Strength

A private iOS app for strength training, food and weekly check-ins, built around
RW Fitness programs. One app, installed on each person's own iPhone; all health
data stays on that phone.

## Build on a Mac

```bash
brew install xcodegen
xcodegen generate                 # creates SteadyStrength.xcodeproj from project.yml
open SteadyStrength.xcodeproj
```

Put your Apple Developer Team ID in `Config/Local.xcconfig` (not committed):

```
DEVELOPMENT_TEAM = ABCDE12345
```

Then pick your iPhone and press Run. Requires Xcode 16+, iOS 17+.

## Layout

| Path | What |
|---|---|
| `App/` | SwiftUI app: onboarding, Face ID lock, Today/Train/Settings, SwiftData models |
| `Packages/SteadyCore/` | Platform-neutral logic with its own tests: program models, swaps, nutrition, strength, lock policy |
| `Resources/Source/` | The original workbooks (never edited) |
| `Resources/Generated/` | JSON built from them by the importer, bundled into the app |
| `tools/importer/` | The importer, exercise catalogue, coach decisions and Python tests ([README](tools/importer/README.md)) |
| `AppTests/`, `AppUITests/` | App unit and UI tests |
| `docs/ARCHITECTURE.md` | Design decisions and the phase plan |

## Tests

```bash
python3 -m unittest discover -s tools/importer        # importer, swaps, session versions
swift test --package-path Packages/SteadyCore          # core logic (macOS)
xcodebuild test -scheme SteadyStrength -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI runs all three on every push (`.github/workflows/ci.yml`).
