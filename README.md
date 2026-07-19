# Sera

Time & goal visualization widget for macOS. Phase 1 MVP: a **menu bar** item with the system glass dropdown that shows live year progress.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+ (full Xcode app, not only Command Line Tools)

## Open & run

1. Open `Sera/Sera.xcodeproj` in Xcode.
2. Select the **Sera** scheme.
3. Set your Development Team under Signing & Capabilities if needed.
4. Press **Run** (⌘R).

The app runs as an accessory (`LSUIElement`) with no Dock icon. Look in the **top menu bar** for the Sera status item (half-circle icon + percent). Click it for the native glass dropdown.

## Interactions (MVP)

| Action | Result |
|--------|--------|
| Click status item | Open system glass dropdown |
| Timelines | Goal selector + style picker |
| Quit Sera | Quit from the dropdown |

## Architecture

- **TimeEngine** — year / goal progress math
- **GoalEngine** — local goal store (`UserDefaults`)
- **MenuBarExtra** — native glass menu bar window (SwiftUI)
- **AppState** — Combine-driven selection, style, live snapshot

## Project layout

```
Sera/
  Sera.xcodeproj
  Sera/
    App/
    Engines/
    Models/
    State/
    Views/
    Utilities/
```

## Roadmap

- **Phase 2** — Visualization styles + animations
- **Phase 3** — Goal create / edit / switch
- **Phase 4** — Richer insights + polish
