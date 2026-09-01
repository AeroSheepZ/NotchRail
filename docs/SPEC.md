# Specification: NotchRail 0.0.3 - Settings System & Interaction Polish

## Problem Statement

While NotchRail (v0.0.2) successfully established a zero-tampering, window-level extended menu bar via SkyLight window enumeration, direct window bitmap capture, and `CGEvent` click routing, user interaction and configuration options remained rigid:

1. **Inflexible Island Triggering**: The island only expanded via hover with a fixed timing model. Users who prefer explicit click activation or who frequently navigate near the top edge suffered from accidental expansions or lack of click-to-open capability.
2. **Missing Interaction Toggles**: Post-click behavior was strictly hardcoded to collapse, haptic feedback was uncustomizable, and the compact pill persistently occupied space even when no items were hidden behind the notch.
3. **Multi-Display Rigidity**: External non-notch displays unconditionally spawned an island that followed the cursor, without allowing users to restrict NotchRail strictly to their built-in MacBook display or disable it on external monitors.
4. **Settings UI Gaps & Incomplete Controls**: The initial settings window lacked live permission re-validation, app search/filtering for blacklist configuration, manual bundle ID entry, and a dependable, prominent way to cleanly quit the application.
5. **No Menu Bar Auxiliary Status Extra**: When running in agent mode (`LSUIElement = true`), users had no persistent tray icon to access settings, initiate re-scans, or safely exit without opening the expanded island.

## Solution

NotchRail 0.0.3 delivers a comprehensive **Settings Architecture & Interaction Polish Suite**:

1. **Multi-Mode Island Triggers (`TriggerMode`)**:
   - `.hover`: Native hover with customizable debounce delay (50–300ms).
   - `.click`: Hover disabled; expansion toggles explicitly upon clicking the compact pill.
   - `.hoverAndClick`: Fast-path expansion on hover, with immediate click-to-toggle support.
2. **Granular Interaction & Visibility Controls**:
   - `autoCollapseOnClick`: Configurable auto-collapse upon successfully dispatching a click to an overflowed item.
   - `enableHapticFeedback`: Haptic vibration feedback via `NSHapticFeedbackManager` during icon clicks and shake failure states.
   - `hideWhenNoOverflow`: Option to completely hide the compact pill when all menu bar items fit natively on screen.
3. **External Display Strategy (`ExternalDisplayMode`)**:
   - `.followFocusedScreen`: Island dynamically follows key window focus and active screen clicks across displays (default).
   - `.mainScreenOnly`: Island strictly anchors to the primary / built-in notch display.
   - `.disabled`: Island is disabled on external non-notch monitors.
4. **Native Auxiliary Status Item (`StatusItemManager`)**:
   - Optional system status bar icon (`tray.full.fill`) providing quick actions: Toggle Island, Rescan Menu Bar, Preferences (⌘,), and Quit NotchRail (⌘Q).
5. **Full-Featured Settings & Diagnostics Experience**:
   - Live status reflection for Accessibility and Screen Recording permissions with instant refresh.
   - App blacklist manager with fuzzy search, running status badges, manual Bundle ID addition, and one-click clear.
   - Explicit "Quit NotchRail" action with system exit coordination (`NSApplication.shared.terminate`).
   - "Reset to Recommended Defaults" button.

## User Stories

1. As a user who dislikes accidental hover triggers, I want to set the island trigger mode to "Click Only", so that the island expands strictly when I click the compact pill.
2. As a user who prefers effortless hover discovery, I want to keep the trigger mode as "Hover", so that pausing my cursor over the notch expands the menu bar automatically.
3. As a power user, I want the trigger mode "Hover or Click", so that I can either hover or click to immediately expand/collapse the island.
4. As a user, I want clicking an overflowed icon to automatically collapse the island by default, so that I can immediately interact with the popped-up application menu.
5. As a user who opens multiple utilities in succession, I want an option to disable "Auto-collapse on click", so that the island stays open after dispatching clicks.
6. As a trackpad user, I want tactile haptic confirmation when clicking icons, so that I receive immediate physical feedback that an action was dispatched.
7. As a user who values sensory customization, I want to toggle haptic feedback on or off in Settings.
8. As a minimalist user, I want an option to automatically hide the compact pill when there are 0 overflowed items, so that my screen stays entirely clean when no icons are hidden.
9. As a user on a multi-monitor desk setup, I want to restrict NotchRail to my built-in MacBook screen only, so that secondary monitors remain completely free of top overlays.
10. As a user with multiple external displays, I want NotchRail to follow my mouse cursor across screens, so that overflowed utilities remain accessible regardless of which display is focused.
11. As a user running NotchRail as a background agent (`LSUIElement`), I want an optional native menu bar status icon, so that I always have a stable access point to settings and actions.
12. As a user clicking the menu bar status icon, I want a menu with options to Toggle Island, Rescan Menu Bar, Open Preferences, and Quit NotchRail.
13. As a user, I want a prominent "Quit NotchRail" button in the Settings window and Menu Bar extra, so that I can cleanly and instantly terminate the app at any time.
14. As a user granting Accessibility permissions in System Settings, I want NotchRail to instantly detect the authorization and show a green "Granted" badge without restarting the app.
15. As a user granting Screen Recording permissions in System Settings, I want NotchRail to immediately reflect permission status and start capturing high-definition icon bitmaps.
16. As a user managing dozens of background apps, I want a search bar in the "Apps" settings tab to quickly filter applications by name or Bundle Identifier.
17. As a user with a specific background helper app that is not currently running, I want to manually type its Bundle ID into the blacklist, so that it will be hidden whenever it launches.
18. As a user reviewing active apps in Settings, I want to see crisp application icons alongside their display state (Overflowed, Visible, Ignored), so that I can easily identify each tool.
19. As a user who made custom timing changes, I want a "Reset to Defaults" button in the Timing tab, so that I can effortlessly revert to factory-calibrated spring and debounce parameters.
20. As a user adjusting hover debounce between 50ms and 300ms, I want changes to immediately update the active state machine without requiring an app restart.
21. As a user adjusting collapse grace delay between 150ms and 600ms, I want changes to take effect in real time.
22. As a user launching NotchRail upon login, I want the `SMAppService` background service registration to sync flawlessly with the Settings toggle.
23. As a user who wants to clear all ignored applications, I want a "Clear All Ignored Apps" button with confirmation, so that I can reset my blacklist in one click.
24. As a user viewing the About tab, I want to see the accurate version number and build string fetched dynamically from the app bundle.
25. As a developer/contributor, I want a direct link to the GitHub repository from the About tab to check for updates or report issues.
26. As a user experiencing temporary display desynchronization, I want a "Rescan Menu Bar" button in Settings and the Tray menu to force an immediate SkyLight scan.
27. As a user switching display resolutions or orientation, I want NotchRail to re-evaluate `ExternalDisplayMode` rules and reposition the panel seamlessly.
28. As a user who hides the tray status icon, I want to still access Settings via the gear icon inside the expanded island or standard macOS `⌘,` keyboard shortcut.
29. As a user upgrading from version 0.0.1/0.0.2, I want my existing preferences (ignored apps, delays) to migrate smoothly without data loss or corruption.
30. As a user running automated tests, I want the full suite of preferences, state transitions, and overflow calculations to pass with zero regressions.

## Implementation Decisions

### 1. Unified Preferences Schema (`UserPreferences`)
- Expanded `UserPreferences` struct conforming to `Codable`, `Equatable`, and `Sendable`:
  - `triggerMode: TriggerMode` (`.hover`, `.click`, `.hoverAndClick`; default: `.hover`).
  - `autoCollapseOnClick: Bool` (default: `true`).
  - `enableHapticFeedback: Bool` (default: `true`).
  - `hideWhenNoOverflow: Bool` (default: `false`).
  - `externalDisplayMode: ExternalDisplayMode` (`.followFocusedScreen`, `.mainScreenOnly`, `.disabled`; default: `.followFocusedScreen`).
  - `showMenuBarIcon: Bool` (default: `true`).
  - `hoverExpandDelayMs: Double` (default: 120.0).
  - `collapseDelayMs: Double` (default: 300.0).
  - `ignoredBundleIDs: [String]` (default: `[]`).
  - `launchAtLogin: Bool` (default: `false`).
  - `skipScreenCapturePrompt: Bool` (default: `false`).

### 2. State Machine & Trigger Mode Pathways (`IslandStateMachine`)
- Extended state machine to support distinct trigger channels:
  - When `triggerMode == .click`: `handleMouseEnter` does not initiate `debounceTimer`. The state remains `.compact` until an explicit tap event calls `toggleExpandCollapse()`.
  - When `triggerMode == .hover`: Standard debounce hover workflow.
  - When `triggerMode == .hoverAndClick`: Hover starts debounce timer, but tapping the compact pill triggers immediate transition to `.extended` or `.compact`.
- Bi-directional reactive binding between `PreferenceStore` and `IslandStateMachine`.

### 3. Native Auxiliary Tray Management (`StatusItemManager`)
- Dedicated manager controlling an `NSStatusItem` in the macOS system status bar:
  - Dynamically shows or hides based on `preferences.showMenuBarIcon`.
  - Populates standard `NSMenu` with:
    - Current status / Quick Expand toggle
    - Immediate "Rescan Menu Bar" action
    - "Preferences..." (opening `SettingsWindowCoordinator`)
    - Separator
    - "Quit NotchRail" (`NSApp.terminate(nil)`)

### 4. Settings Window Redesign (`SettingsView`)
- Structured 4-tab modern macOS layout:
  - **General**: Trigger Mode picker, auto-collapse toggle, haptic feedback toggle, hide-when-empty toggle, multi-display strategy picker, show tray icon toggle, launch at login toggle, and red-bordered "Quit NotchRail" button.
  - **Timing & Dynamics**: Debounce slider (50–300ms), Collapse delay slider (150–600ms), and "Reset to Defaults" button.
  - **Apps (Blacklist)**: Search bar filter, list of running items with bundle icons, title, bundle ID, display mode badges, blacklist toggles, manual Bundle ID input field, and "Clear All" button.
  - **About & Health**: Live permission badges (Accessibility & Screen Recording) with refresh buttons, app icon & version metadata, GitHub repo button, and duplicate Quit button.

### 5. Multi-Display Coordination (`IslandWindowCoordinator` & `ScreenManager`)
- `IslandWindowCoordinator` observes `PreferenceStore.preferencesChanged`:
  - If `externalDisplayMode == .mainScreenOnly` and current screen is not the primary screen, panel hides or stays anchored on `NSScreen.screens.first`.
  - If `externalDisplayMode == .disabled` and current screen is external, panel stays hidden.
  - If `hideWhenNoOverflow == true` and `snapshot.overflowCount == 0`, panel alpha smoothly animates to 0.

## Testing Decisions

- **Good Test Philosophy**: Focus strictly on observable behavioral contracts (preference encoding/decoding, fallback defaults, migration safety, state machine trigger transitions, and overflow blacklist calculation) without mocking internal UI views.
- **Modules Tested**:
  1. `PreferenceStoreTests`:
     - Default values verification.
     - JSON serialization & deserialization with legacy compatibility.
     - `resetToDefaults()` correctness.
     - Adding/removing ignored Bundle IDs.
  2. `IslandStateMachineTests`:
     - Hover trigger transitions under `.hover`, `.click`, and `.hoverAndClick` modes.
     - Tap toggle transitions.
     - Debounce cancellation on rapid mouse leave.
  3. `OverflowCalculatorTests`:
     - Verify blacklist filtering on overflow item partitioning.
- **Prior Art**: Builds on existing `Tests/NotchRailTests/` suite.

## Out of Scope

- Custom global hotkey daemon registration using low-level Carbon Event taps (deferred to 0.0.4+ to prevent conflicts with native Spotlight/Raycast).
- Re-architecting SkyLight bridge or replacing `CGEvent.postToPid`.
- Injecting third-party menu bar spacers.

## Further Notes

- Target Deployment: macOS 14.0+ (Sonoma / Sequoia).
- Zero external package dependencies; uses native Swift, SwiftUI, AppKit, Combine, and CoreGraphics.
