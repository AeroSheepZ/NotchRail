# Specification: NotchRail 0.0.5 - Full-Screen Immersive Space Coordination & Edge Awakening

## Problem Statement

When macOS users transition into Native Full-Screen Spaces (e.g. Xcode, Safari, Video Players, Keynote, Terminal), macOS automatically hides the system menu bar to maximize screen estate and provide a distraction-free environment. 

In previous versions of NotchRail (v0.0.4 and earlier):
1. **Persistent Visual Occlusion in Full Screen**: The compact island panel remained permanently pinned below the MacBook physical notch or top display edge regardless of workspace mode, intruding upon full-screen videos, slides, games, and code editors.
2. **Disconnected Space Dynamics**: When the user pushed the cursor to the top edge to reveal the native macOS menu bar in full screen, NotchRail did not coordinate with the system's reveal animation, causing an asynchronous or jarring visual mismatch.
3. **Lack of Immersive Auto-Collapse**: There was no zero-cost, private-API-free mechanism to smoothly fade out the compact island when entering full-screen spaces and smoothly awaken it when the user intentionally accesses the top edge.

## Solution

NotchRail 0.0.5 delivers **Full-Screen Immersive Space Coordination & Edge Awakening**:

1. **Zero-Overhead Geometric Full-Screen Detection**:
   - Compares visible screen frame height against total display frame height (`screen.visibleFrame.height == screen.frame.height`) to instantaneously detect when the active workspace has hidden the native menu bar, with zero thread polling overhead.
2. **Top-Edge Hot-Zone Awakening (Edge Trigger)**:
   - When the cursor reaches the top boundary ($Y \le 2\text{pt}$ from screen top) within a full-screen space, NotchRail smoothly fades in the standard Compact Island (including dynamic ear wings and overflow badge) in harmony with the descending macOS menu bar.
3. **Standard Compact Awakening State**:
   - Preserves standard desktop mental models: the awakened island appears as the familiar Compact Island, allowing users to hover (with debounce) or click to expand into the Extended Menu Bar.
4. **Graceful Auto-Fadeout**:
   - When the cursor moves away from the top edge and out of the island interaction zone, the island gracefully fades out after a configurable grace period, restoring complete full-screen immersion.

## User Stories

1. As a full-screen code editor user, I want the compact island to automatically hide when I maximize Xcode or VS Code to full screen, so that my editor utilizes the entire screen without any floating overlay.
2. As a video viewer watching full-screen movies, I want NotchRail to disappear completely during playback, so that no pill or wing badge covers the video content.
3. As a presenter giving a full-screen Keynote slideshow, I want the island to remain invisible during presentation mode, so that slides appear entirely clean to the audience.
4. As a full-screen user who needs to check an overflowed status utility, I want pushing my mouse to the top edge of the screen to smoothly reveal the compact island alongside the system menu bar.
5. As a trackpad user in full-screen mode, I want the awakened island to show the exact overflow count badge and ear wings, so that I immediately know how many items are hidden behind the notch.
6. As a user interacting with the awakened island in full screen, I want hovering or clicking the compact pill to expand the full row of overflowed items just like on standard desktop spaces.
7. As a user clicking an item in full-screen mode, I want the click to route seamlessly to the target window, so that I can trigger popovers or dropdowns while remaining in full screen.
8. As a user moving my mouse away from the top edge back into my full-screen document, I want the island to fade out smoothly without abrupt flickering.
9. As a multi-monitor user with one screen in full-screen and another in desktop mode, I want full-screen immersion to be evaluated independently per display, so that desktop displays keep their standard persistent island while full-screen displays stay immersive.
10. As a user switching between desktop Spaces and full-screen Spaces via swipe gestures, I want NotchRail to update its visibility state instantly upon space transition.
11. As a user with "Hide when no overflow" enabled, I want full-screen edge detection to respect zero-overflow rules, so that no empty pills awaken on screens with zero hidden icons.
12. As a battery-conscious MacBook user, I want full-screen edge monitoring to add zero background CPU cycles, so that my battery life is completely unaffected.

## Implementation Decisions

### 1. Geometric Detection Contract
- Utilize the delta between `screen.frame` and `screen.visibleFrame` as the canonical indicator for menu bar auto-hidden / full-screen state:
  - When `visibleFrame.maxY == frame.maxY`, the system menu bar is collapsed (Full-Screen Space).
  - When `visibleFrame.maxY < frame.maxY`, the system menu bar is permanently occupying the top status band (Desktop Space).
- Bind detection directly into screen parameter notifications and mouse coordinate updates without spawning background polling timers.

### 2. Edge Awakening State Transition
- Extend the `IslandDisplayState` state machine or overlay coordination pipeline with a transient `fullScreenHidden` state:
  - Entering Full-Screen Space $\implies$ Island alpha transitions to `0.0` with standard spring easing.
  - Cursor reaching top boundary ($Y \le 2\text{pt}$) $\implies$ Island transitions to standard `compact` with alpha `1.0`.
  - Cursor leaving island and top boundary $\implies$ Island fades out after grace period (default 300ms).

### 3. Pure Public API Boundaries & AX Spatial Verification
- Strictly avoid private SkyLight Space notification APIs (`CGSGetActiveSpace`) to guarantee zero deprecation risks and full forward-compatibility across macOS 14, 15, and future releases.
- Coordinate edge events through existing `MouseMonitor` global event streams (`kCGEventMouseMoved`).
- For multi-space and external display isolation in background agent mode (`LSUIElement = true`), verify frontmost application window status via public Accessibility API (`AXFullScreen` attribute) in normalized Quartz display coordinates (`CGDisplayBounds`).

### 4. Pure Geometric Physical Overflow Calculation
- Overflow status must be evaluated exclusively against physical screen and notch geometric boundaries (`frame.minX < notchRightEdge + 12.0` or out-of-screen bounds).
- Never rely on transient WindowServer visibility markers like `!item.isOnScreen`, because macOS collapses status bar items in full screen and space transitions, which would misclassify normal visible items as overflowed.

### 5. Settings App Management Native macOS UI
- App management list conforms to native macOS System Settings styling: `Color(nsColor: .controlBackgroundColor)`, `.primary`, `.secondary`, and native `Divider()`.
- Provides a dedicated high-contrast dark tile container for status bar icons to ensure white and monochrome icons remain distinct across both light and dark system appearances.

## Testing Decisions

### Good Test Philosophy
- Focus exclusively on observable behavioral contracts (geometric calculations, edge coordinate predicates, space change events, and state machine transitions) without mocking private AppKit internals.

### Modules Tested
1. `ScreenManagerTests`:
   - Verify `isFullScreenSpace` geometric calculation under varying `frame` and `visibleFrame` mock configurations.
   - Verify multi-display independence (Display A in full-screen while Display B is desktop).
2. `IslandStateMachineTests`:
   - Verify transition from `fullScreenHidden` to `compact` upon top-edge trigger ($Y \le 2\text{pt}$).
   - Verify transition back to `fullScreenHidden` upon mouse leave after grace timeout.
   - Verify hover expansion transitions while in awakened full-screen compact state.
3. `MouseMonitorTests`:
   - Verify edge threshold evaluations ($Y \le 2\text{pt}$) across display coordinate systems.

### Prior Art
- Builds upon existing `Tests/NotchRailTests/IslandStateMachineTests.swift` and `ScreenManagerTests.swift`.

## Out of Scope

- Hooking native macOS full-screen window transition animations.
- Modifying macOS Mission Control or Space reordering behavior.
- Supporting legacy macOS versions prior to macOS 14.0 (Sonoma).

## Further Notes

- Target Deployment: macOS 14.0+ (Sonoma / Sequoia).
- Zero external package dependencies; uses native Swift, SwiftUI, AppKit, Combine, and CoreGraphics.
