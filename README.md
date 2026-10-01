# Magenda

An iOS app.

## Build and run

You need a Mac with Xcode (with the iOS simulator runtimes) and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate            # writes Magenda.xcodeproj from project.yml
open Magenda.xcodeproj
```

The `.xcodeproj` is generated and never committed (ADR 0003): run `xcodegen generate` again after
a pull that changed `project.yml`, and make project changes in `project.yml`, not in Xcode's
project editor.

The app's logic is in `AppCore/`, a Swift package that also builds on Linux (ADR 0007):

```bash
swift test --package-path AppCore
```

## Layout

| Path | What it is |
|---|---|
| `App/` | The SwiftUI app: views, navigation, assets |
| `AppCore/` | The app's logic, as a Swift package with its own tests |
| `AppTests/` | Tests that run inside the built app on a simulator |
| `AppUITests/` | UI tests that drive the app on a simulator |
| `project.yml` | The Xcode project's specification (XcodeGen) |
| `scripts/` | Release, coverage and simulator helpers, with their tests |

## Documentation

- [`docs/README.md`](docs/README.md) — index of the contributor docs.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how to contribute.
- [`CHANGELOG.md`](CHANGELOG.md) — what changed in each release.
