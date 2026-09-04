# NotchRail

Extended Menu Bar for MacBook Notch and external flat displays.

## Language

**MenuBarItem**:
A status bar window element enumerated from WindowServer (Layer 25) and mapped to an application via accessibility coordinates.
_Avoid_: StatusItem, TrayIcon, MenuIcon, StatusWindow

**PhysicalNotch**:
The physical hardware notch cut-out on modern MacBook displays (`hasPhysicalNotch == true`), serving as the primary geometric anchor for NotchRail.
_Avoid_: FakeNotch, SimulatedNotch, VirtualNotch

**OverflowItem**:
A MenuBarItem whose physical horizontal geometry intersects the notch safety margin on a physical notch display, or collides with the active application's menu boundary on an external display.
_Avoid_: HiddenItem, OccludedItem, CrowdedItem

**AppMenuBoundary**:
The dynamic horizontal rightmost boundary of the frontmost application's main menu items on a non-notch display, serving as the physical collision threshold for status bar overflow.
_Avoid_: LeftMenuEdge, AppMenuOffset

**FloatingShelf**:
The expanded presentation form factor of IslandPanel on non-notch flat displays, featuring top-edge flush docking (`topEarRadius = 0.0`) and zero-presence idle state.
_Avoid_: FakeNotchShelf, ExternalPill

**ViewportLease**:
The window coordination mechanism where the single IslandPanel instance permanently guards the physical notch display and is temporarily leased to an external display strictly during an active hover expansion.
_Avoid_: WindowRelocation, ScreenMirroring

**CapturedIcon**:
A pixel-perfect bitmap snapshot of a MenuBarItem with dynamic transparent margin trimming and visual equality comparison (`isVisuallyEqual`).
_Avoid_: AppDockIcon, GenericSymbol, ScaledThumbnail

**PulsingCapsule**:
The neutral breathing placeholder rendered while a MenuBarItem is in its initial capture or refresh cycle.
_Avoid_: LoadingSpinner, GrayBox, PlaceholderIcon

**IslandPanel**:
The top-anchored, hardware-level pass-through floating viewport hosting NotchRail's presentation layer.
_Avoid_: NotchShelf, FloatingBar, OverlayWindow

**StableViewport**:
A permanent, fixed-dimension floating window frame (height 84pt) that eliminates WindowServer surface reallocation during expansion and collapse animations.
_Avoid_: DynamicWindowFrame, ResizingPanel

**HardwarePassthrough**:
The hit-testing and event routing mechanism dynamically toggling `ignoresMouseEvents` so that all transparent pixels outside the active capsule or island pass 100% to underlying applications.
_Avoid_: TransparentClickCapture, BackgroundClickMask

**CompactIsland**:
The idle, minimal pill state of IslandPanel hugging the notch contour and displaying the dynamic wing badge on physical notch displays.
_Avoid_: MiniNotch, SmallPill, IdleCapsule

**ExtendedMenuBar**:
The expanded state of IslandPanel rendering the zero-fallback mirrored bitmap icons of all overflow items.
_Avoid_: ExpandedIsland, DropdownBar, OverflowMenu

**NativeMenuAnchor**:
The original physical coordinate of a MenuBarItem where native dropdown menus pop up upon synthetic CGEvent dispatch.
_Avoid_: FloatingMenuAnchor, DetachedMenu

**FullScreenStealth**:
The dormant state where IslandPanel fades out (`alpha = 0`, `ignoresMouseEvents = true`) in full-screen spaces to prevent obscuring user content.
_Avoid_: FullScreenDisabled, HiddenInFullScreen

**TopEdgeHotZone**:
The physical screen top boundary hot-zone that triggers the smooth wake-up or on-demand expansion of IslandPanel.
_Avoid_: WakeUpTriggerLine, TopHoverMargin
