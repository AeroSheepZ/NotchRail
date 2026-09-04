# Specification: NotchRail 0.0.6 - External Non-Notch Display Dynamic Collision Detection & On-Demand Floating Shelf

## Problem Statement

macOS users utilizing external flat displays (or non-notch Mac hardware such as Mac mini, Mac Studio, or MacBook in clamshell mode) face fundamental architectural and user experience flaws in existing menu bar expansion tools:

1. **Artificial "Fake Notch" Occlusion**: Traditional utilities hardcode a synthetic 160pt notch in the center of non-notch flat displays, permanently rendering an unnatural pitch-black capsule that obscures clean desktop wallpapers, clutters the menu bar, and obstructs underlying browser tabs and editor headers.
2. **Fabricated "Ghost Overflow"**: Because algorithms presume an imaginary notch obstacle in the center of the display, status bar items simply crossing the screen midpoint are falsely flagged as "overflowed" and duplicated inside the floating overlay, despite being 100% visible and unoccluded in the native menu bar.
3. **Blindness to Real Native Menu Bar Collisions**: On macOS, real menu bar overflow without a physical notch occurs strictly when the left-hand application menu (File, Edit, View...) collides with the right-hand status item row, prompting macOS WindowServer to silently drop and unmap the leftmost third-party icons. Existing utilities fail to track this dynamic collision boundary, remaining completely oblivious when third-party icons are truly swallowed by heavyweight professional applications (e.g. Xcode, Photoshop, Logic Pro).
4. **Single-Viewport Cross-Screen Tearing**: Because the system manages a single global `IslandPanel` instance, moving the cursor to an external monitor abruptly relocates the window frame, stripping away the compact capsule and dynamic yellow ear wings from the MacBook's physical notch and leaving it completely bare.
5. **Accidental Expansion on Top-Edge Interactions**: Naive edge triggers that listen across the entire display width intercept user clicks targeting top-left application menus (File, Edit) or top-right system status items (Clock, Wi-Fi, Control Center), causing disruptive overlays during standard menu usage.
6. **False Triggers in Vertical Multi-Monitor Setups**: When displays are stacked vertically, moving the mouse downwards from an upper display crosses the lower display's top boundary at high velocity, inadvertently triggering an unwanted expansion without dwell intent.
7. **Full-Screen Space Collision**: When an external display is in full-screen space (e.g. full-screen video or IDE), touching the top edge causes both the macOS native full-screen menu bar and the floating island to drop down simultaneously, resulting in double dark bars occluding the clock and native menus.

## Solution

NotchRail 0.0.6 introduces **External Non-Notch Display Dynamic Collision Detection & On-Demand Floating Shelf**:

```
                              [User Multi-Display Workspace]
                                             │
        ┌────────────────────────────────────┴────────────────────────────────────┐
        ▼                                                                         ▼
【MacBook Built-In Notch Screen】                                         【External Flat Display (Non-Notch)】
• Physical Invariant: Camera cutout centered on top                       • Physical Invariant: Zero hardware obstructions
• Overflow Formula: minX < notchRightEdge + 24pt                          • Overflow Formula: minX < (AppMenuBoundary + 12pt)
• Idle State: Permanent black capsule + yellow ear wings                  • Idle State: 100% Invisible (Zero-presence, zero fake notch)
• Expansion Form: Liquid drop-down fluid expansion                        • Expansion Form: Central 240pt hot-zone 120ms dwell reveal
• Viewport Ownership: Permanent home anchor of IslandPanel                • Viewport Ownership: Temporarily leased on expansion, returned on collapse
```

1. **Zero-Presence Idle State on Flat Displays**: On non-notch displays (`hasPhysicalNotch == false`), NotchRail completely eliminates fixed fake notch placeholders. The idle state is 100% invisible (`alpha = 0.0`, `ignoresMouseEvents = true`), leaving the native menu bar pristine and unobstructed.
2. **Dynamic Application Menu Collision Detection**: Replaces the hardcoded 160pt center virtual notch with real-time tracking of the active application's menu bar right boundary (`AppMenuBoundary`). A status item is deemed an `OverflowItem` on external displays if and only if its horizontal position collides with the active application's menu boundary (`item.minX < AppMenuBoundary + 12pt`) or exceeds the physical display bounds.
3. **Restricted Top-Center Hot-Zone with Dwell Gate**: An edge awakening zone restricted to the top center ($\pm 120\text{pt}$ horizontally, $\le 4\text{pt}$ vertically) with a mandatory 120ms dwell filter. Users moving the cursor across the top edge or interacting with native menus (File/Edit or Clock/Wi-Fi) will never accidentally trigger the floating shelf.
4. **Viewport Leasing Architecture ("Notch Guard, External Lease")**: The single `IslandPanel` instance permanently guards the MacBook's physical notch display, maintaining its dynamic ear wings and badge. Only when an external display actively triggers an expansion does the panel atomically lease to the external display, smoothly sliding out as a flat-docked `FloatingShelf` (`topEarRadius = 0.0`). Upon collapse, the panel seamlessly returns to guard the physical notch.
5. **Immediate Dismiss on Outside Click**: Clicking anywhere outside the expanded floating shelf immediately dismisses the overlay with zero click lag to underlying applications.
6. **Zero-Overflow Mute Gate**: If an external display has zero collided/overflowed items, the top-center edge hot-zone remains strictly dormant, ensuring zero unwanted popups.
7. **Full-Screen Space Yielding**: In full-screen spaces on external displays, edge detection yields priority to the native macOS descending menu bar, avoiding double dark bar occlusion.

## User Stories

1. As an external 4K monitor user, I want zero black notch capsules rendered at the top of my display, so that my desktop wallpaper and native menu bar remain completely clean and unoccluded.
2. As a MacBook user connected to an external screen, I want the compact island and yellow overflow badge to remain visible on my MacBook's physical notch when my mouse is on the external display, so that I can glance at my laptop and always see my overflow status.
3. As a developer using Xcode with extensive menus on an external monitor, I want NotchRail to detect when Xcode's menus push my third-party status icons off the screen, so that those swallowed icons are accurately captured in the overflow list.
4. As a user working in Finder with only four short menu titles, I want NotchRail to recognize that my menu bar has ample free space, so that none of my visible status icons are duplicated into the floating shelf.
5. As an external display user with no occluded icons, I want the top-center edge of my screen to ignore mouse passes, so that I am never disturbed by an empty overlay appearing.
6. As a user with an occluded icon on my external display, I want moving my mouse to the top-center edge and pausing for a moment (120ms) to smoothly reveal the floating shelf, so that I can easily access my hidden tools.
7. As a user rapidly flicking my cursor across the top edge of my screen, I want NotchRail to ignore the gesture, so that rapid mouse movements never trigger accidental expansions.
8. As a user clicking the Apple logo or File menu in the top-left corner, I want the top-center expansion to remain dormant, so that my standard menu interactions are never intercepted.
9. As a user checking the clock or Wi-Fi status in the top-right corner, I want the expansion trigger to remain dormant, so that system tray clicks work normally without obstruction.
10. As a user viewing the expanded floating shelf on an external flat monitor, I want the shelf to dock flush against the top edge without curved ear horns, so that it looks like a native macOS floating HUD rather than a phone cutout.
11. As a user who expanded the floating shelf on an external monitor, I want clicking any of the mirrored icons to trigger its native menu directly at its physical window coordinates, so that I can configure my apps as usual.
12. As a user who accidentally expanded the floating shelf, I want clicking anywhere outside the shelf on my web browser to immediately dismiss the shelf while registering my browser click, so that my workflow is uninterrupted.
13. As a user moving my mouse away from the floating shelf, I want it to smoothly slide up and fade out after a 300ms grace period, so that my screen returns to its clean state.
14. As a clamshell mode user with my MacBook lid closed, I want NotchRail to operate normally on my external monitor without crashing or expecting a non-existent physical notch, so that desktop docking setups work seamlessly.
15. As a vertical multi-monitor user with an external screen mounted above my MacBook, I want moving my cursor downwards across the display border to avoid false triggers, so that vertical navigation is smooth.
16. As a full-screen video watcher on an external display, I want pushing my mouse to the top edge to prioritize revealing the native macOS menu bar rather than covering it with a floating shelf, so that I can check the system clock without visual obstruction.
17. As a multi-monitor user switching between displays, I want the active application's menu boundary to be evaluated specifically against the targeted display's coordinate span, so that multi-display coordinate offsets never corrupt collision math.
18. As a performance-conscious user, I want application menu boundary queries to be event-driven rather than polled on every mouse move, so that my CPU and battery consumption remain negligible.
19. As a user with an ultra-wide (34" or 49") display, I want the floating shelf to anchor in the horizontal center with a balanced maximum width (up to 760pt), so that icons remain easily accessible and do not stretch across the entire screen.
20. As a user switching dark and light desktop wallpapers, I want the floating shelf to utilize native macOS ultra-thin frosted glass materials, so that it blends seamlessly with any wallpaper tone.
21. As a user changing display resolution or scaling settings, I want NotchRail to immediately recalculate screen boundaries and the menu collision line, so that overflow items remain accurately identified.
22. As a user with dynamic menu bar utilities (e.g. live CPU meter, upload/download network speeds), I want numerical updates inside the floating shelf to refresh without causing the entire overlay to jitter or jump in size.
23. As a user in macOS System Settings configuring displays, I want moving the menu bar arrangement to take effect immediately without needing to restart NotchRail.
24. As a user running DaVinci Resolve or Adobe Premiere with heavy custom menu items, I want NotchRail to accurately extract the furthest right menu boundary even when third-party menus have custom accessibility labels.
25. As a user returning from an external screen back to my MacBook, I want the compact island on my laptop's physical notch to immediately become interactive without lag.
26. As a user who customized "Ignored Apps" in preferences, I want those ignored items to remain hidden from the external floating shelf just as they are on the MacBook notch.
27. As a user invoking NotchRail via the macOS status bar tray menu, I want clicking "Scan & Expand" to expand the floating shelf on the currently focused display.
28. As a QA engineer running automated tests, I want all overflow math to be testable with zero dependencies on physical screens, so that CI/CD runs with 100% predictability.

## Implementation Decisions

### 1. Dual-Track Geometric Collision Resolver

Structurally modify the overflow calculation engine to enforce two mutually exclusive physical tracks as a pure function:

```swift
// Decision Prototype Shape: Dual-Track Resolution Contract
public enum OverflowCalculator {
    public static let NOTCH_CORNER_SAFETY_MARGIN: CGFloat = 24.0
    public static let APP_MENU_COLLISION_SAFETY_MARGIN: CGFloat = 12.0
    public static let SCREEN_EDGE_TOLERANCE: CGFloat = 5.0

    public static func resolve(
        items: [MenuBarItem],
        geometry: NotchGeometry,
        ignoredBundleIDs: Set<String> = []
    ) -> MenuBarSnapshot {
        let isNotch = geometry.hasPhysicalNotch
        let collisionBoundary: CGFloat = isNotch
            ? (geometry.physicalNotchRect.maxX + NOTCH_CORNER_SAFETY_MARGIN)
            : ((geometry.appMenuRightEdge ?? (geometry.screenFrame.minX + 180.0)) + APP_MENU_COLLISION_SAFETY_MARGIN)

        let screenMinX = geometry.screenFrame.minX
        let screenMaxX = geometry.screenFrame.maxX

        // Item overflows if its left edge breaches the collision boundary
        // or extends outside physical display bounds
        ...
    }
}
```

- **Physical Notch Track (`hasPhysicalNotch == true`)**:
  - Bound by hardware notch geometry: `item.nativeFrame.minX < (notchRightEdge + 24.0)`.
- **Flat Non-Notch Track (`hasPhysicalNotch == false`)**:
  - Bound by dynamic application menu collision: `item.nativeFrame.minX < (appMenuRightEdge + 12.0)`.
  - `physicalNotchRect` for flat displays is permanently set to `.zero`.

### 2. Event-Driven Application Menu Boundary Extraction (`AppMenuBoundary`)

- Bind menu boundary detection strictly to system workspace events:
  - `NSWorkspace.didActivateApplicationNotification` (frontmost app changed)
  - `NSWorkspace.activeSpaceDidChangeNotification` (Space/Desktop changed)
  - `NSApplication.didChangeScreenParametersNotification` (display topology changed)
- Extraction logic executes asynchronously in background tasks:
  1. Retrieve frontmost application PID (`NSWorkspace.shared.frontmostApplication.processIdentifier`).
  2. Query `kAXMenuBarAttribute` $\implies$ `kAXChildrenAttribute` (`[AXUIElement]`).
  3. Locate the rightmost child item and compute its Quartz coordinates: `item.position.x + item.size.width`.
  4. Cache value in `ScreenManager.frontmostAppMenuMaxX`.
- Baseline fallback: If accessibility returns empty or the active application is Finder, fall back to `screen.frame.minX + 180.0pt` (standard Apple logo + app title reservation).

### 3. Viewport Leasing Architecture ("Notch Guard, External Lease")

Manage the global singleton `IslandPanel` through a strict leasing lifecycle:

```
[Normal Idle State]
   IslandPanel securely anchored to MacBook Physical Notch (alpha = 1.0, compact capsule active)
   External Flat Display has 0 windows (alpha = 0.0, ignoresMouseEvents = true)
        │
        ▼ (User hovers top-center hot-zone on External Display for >= 120ms with overflowCount > 0)
[Lease Acquisition]
   Panel frame atomically shifts to External Display top-center (x = centerX - width/2, y = screenMaxY - 84)
   Presentation morphs to FloatingShelf (topEarRadius = 0.0, alpha = 1.0, ignoresMouseEvents = false)
        │
        ▼ (Mouse leaves for 300ms OR user clicks outside)
[Lease Release & Return]
   Panel collapses with slide-up fade (0.2s duration)
   Panel frame atomically returns to MacBook Physical Notch (restoring compact capsule & ear wings)
```

- **Clamshell Mode Fallback**: When no display possesses a physical notch (`allGeometries.contains(where: { $0.hasPhysicalNotch }) == false`), the panel remains assigned to the primary external display in a dormant `alpha = 0.0` state, expanding in place on demand.

### 4. Edge Interaction & Central Hot-Zone Architecture

- **Spatial Constraints**:
  - Horizontal span: Screen center $\pm 120\text{pt}$ (total 240pt width).
  - Vertical depth: Screen top edge $\le 4\text{pt}$.
- **Temporal Filter (120ms Dwell)**:
  - Cursor entering hot-zone initiates a 120ms non-repeating timer (`dwellTimer`).
  - If cursor exits or moves at high velocity ($> 300\text{pt/s}$ vertical traversal) before expiration, timer cancels with zero state mutation.
- **Zero-Overflow Mute Gate**:
  - If `effectiveSnapshot.overflowCount == 0`, hot-zone evaluation aborts immediately, guaranteeing zero unwanted popups.

### 5. Outside Click Dismissal (Dismiss on Click Outside)

- Extend global mouse click monitor (`MouseMonitor.handleClick`):
  - When `IslandStateMachine.currentState.isExpanded == true`:
  - Check whether click location falls within the active floating shelf interactive bounds (`interactiveBounds.insetBy(dx: -4, dy: -4)`).
  - If outside, immediately call `IslandStateMachine.shared.triggerCollapse()`.
  - The click event itself continues unhindered to the underlying application.

### 6. Visual Presentation & Form Factor on Flat Displays

- In `IslandBackground`:
  - When target screen has `hasPhysicalNotch == false`, enforce `topEarRadius = 0.0`.
  - Render top edge flush against the display border with smooth bottom corner radii (24pt).
  - Material: Native macOS HUD frosted glass (`.ultraThinMaterial`) with subtle border highlight (`white.opacity(0.15)`) and system soft shadow (`color: black.opacity(0.18), radius: 12, y: 4`).

## Testing Decisions

### What Makes a Good Test
- Tests must verify observable contracts and mathematical invariants without inspecting internal actor state or mock implementations.
- Geometry and collision calculations must execute as pure functions using deterministic mock fixtures (`NotchGeometry` and `MenuBarItem` structs).

### Tested Modules & Test Seams

1. **Primary Seam: `OverflowCalculator.resolve`**:
   - *Test Case 1 (Hardware Notch Baseline)*: Ensure physical notch displays maintain the exact 24pt corner safety margin and unchanged snapshot counts.
   - *Test Case 2 (Flat Display Wide Open Space)*: 2560pt display with short App menu ($x = 400$) and 15 items spanning $x = 1800 \dots 2560 \implies$ Verify `overflowCount == 0` (zero ghost overflow).
   - *Test Case 3 (Flat Display Real Xcode Collision)*: 1920pt display with heavy App menu ($x = 1100$) and items extending leftwards to $x = 1050 \implies$ Verify items with $minX < 1112$ are marked `.overflowed` and rightmost items remain `.nativeVisible`.
   - *Test Case 4 (Out-of-Screen Handling)*: Items with $maxX > screenMaxX + 5$ or $maxX < screenMinX$ marked `.overflowed`.
   - *Test Case 5 (Ignored Bundle IDs)*: Items in ignored list strictly marked `.ignored`.

2. **Secondary Seam: `IslandStateMachine` State Flows**:
   - Dwell timer expiration triggers `.extended`.
   - Early exit before 120ms resets to `.compact`.
   - Mouse leave triggers `.collapsing` with 300ms grace period.
   - Mouse re-entry during collapsing cancels collapse timer.
   - External click invokes `triggerCollapse()` immediately.

3. **Tertiary Seam: `ScreenManager` Topology**:
   - Non-notch display reports `physicalNotchRect == .zero` and `hasPhysicalNotch == false`.
   - Primary geometry selection correctly identifies physical notch screen even when external screen is set as main display.

### Prior Art
- Builds directly upon `OverflowCalculatorTests.swift`, `IslandStateMachineTests.swift`, and `ScreenManagerTests.swift`.

## Failure Pre-Mortem & Mitigation Matrix

| Failure Mode | Early Warning Signal | Root Cause | Architectural Mitigation |
| :--- | :--- | :--- | :--- |
| **AX IPC Hang / Latency Spike** | Main thread hitching $> 50\text{ms}$ on app switch | Synchronous `AXUIElement` traversal blocking RunLoop | Run extraction in detached background Task; query only top-level menu children ($< 10$ items); cache in atomic memory variable. |
| **Viewport Tearing on Multi-Screen** | Laptop notch pill disappears when moving mouse to secondary screen | Global panel relocated to external display during idle | Implement Viewport Leasing: panel stays permanently on physical notch during idle; leased to external only during active expansion. |
| **Menu Collision in Full Screen** | Double dark bars covering native clock in full-screen video | External display top edge trigger firing over descending macOS menu | Check `isFullScreenSpace`: in full-screen spaces, yield to native menu bar; require hover dwell on the visible menu bar to trigger island. |
| **Vertical Screen Transit False Trigger** | Island pops up when moving cursor down from top monitor | Cursor crosses top edge coordinate during transit | 120ms dwell timer + downward velocity check cancels trigger on fast vertical transit. |

## Out of Scope

- User-draggable custom positioning of the floating shelf.
- Drag-and-drop manual reordering of icons within the floating shelf.
- Custom theming/color overrides for the floating shelf background.
- Support for macOS 13 (Ventura) or older.

## Further Notes

- Performance budget: Menu boundary query $< 1\text{ms}$ (event-driven); geometric overflow calculation $< 0.01\text{ms}$ (pure arithmetic); idle background CPU overhead $0.0\%$.
- Eliminates over 100 lines of legacy virtual notch compensation code while adhering 100% to Fail-Fast and Zero-Fallback architectural invariants.
