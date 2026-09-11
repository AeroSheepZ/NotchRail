# NotchRail

Extended Menu Bar for MacBook Notch and external flat displays.

本文件是**领域术语表**：只定义领域语言（词义与禁用别名），**不含任何实现细节**
（不写数值、不写代码标识符、不写类型签名）。实体与枚举的结构、签名见 `docs/DOMAIN_MODEL.md`；
架构不变量与协作纪律见 `AGENTS.md`（归属矩阵见其 §0）。

## Language

**MenuBarItem**:
A status bar window element enumerated from the WindowServer window layer and mapped to an application via accessibility coordinates.
_Avoid_: StatusItem, TrayIcon, MenuIcon, StatusWindow

**PhysicalNotch**:
The physical hardware notch cut-out on modern MacBook displays, serving as the primary geometric anchor for NotchRail.
_Avoid_: FakeNotch, SimulatedNotch, VirtualNotch

**PrimaryDisplay**:
The display owning the primary panel — the physical notch screen or the built-in screen; in a notchless setup (clamshell mode, Mac mini) it is the system main display.
_Avoid_: MainScreen, DefaultDisplay, HostScreen

**OverflowItem**:
A MenuBarItem whose physical horizontal geometry intersects the notch safety margin on a physical notch display, or collides with the active application's menu boundary on an external display.
_Avoid_: HiddenItem, OccludedItem, CrowdedItem

**AppMenuBoundary**:
The dynamic horizontal rightmost boundary of the frontmost application's main menu items on a non-notch display, serving as the physical collision threshold for status bar overflow.
_Avoid_: LeftMenuEdge, AppMenuOffset

**CapturedIcon**:
A pixel-perfect bitmap snapshot of a MenuBarItem with dynamic transparent-margin trimming and visual-equality comparison.
_Avoid_: AppDockIcon, GenericSymbol, ScaledThumbnail

**ApplicationAssetVault**:
The global icon registry keyed by process bundle identifier, holding real bitmaps captured by any active display. A non-focused display resolves its icons straight from the vault by its own confirmed bundle identifier — no pairing, no fallback, no mismatch. It compensates for WindowServer suspending menu item rasterization on non-focused displays.
_Avoid_: IconPool, BitmapStore, WindowPairing

**PulsingCapsule**:
The neutral breathing placeholder rendered while a MenuBarItem is in its initial capture or refresh cycle.
_Avoid_: LoadingSpinner, GrayBox, PlaceholderIcon

**IslandPanel**:
The top-anchored, hardware-level pass-through floating viewport hosting NotchRail's presentation layer. The topology is dual-instance: a primary panel permanently guards the primary display, while an external panel independently serves the single external flat display.
_Avoid_: NotchShelf, FloatingBar, OverlayWindow, SingletonPanel

**StableViewport**:
A permanent, fixed-dimension floating window frame that eliminates WindowServer surface reallocation during expansion and collapse animations.
_Avoid_: DynamicWindowFrame, ResizingPanel

**HardwarePassthrough**:
The hit-testing and event routing mechanism that toggles the panel's mouse-event passthrough, so that all transparent pixels outside the active capsule or island pass fully to underlying applications.
_Avoid_: TransparentClickCapture, BackgroundClickMask

**CompactIsland**:
The idle, minimal pill state of an island panel hugging the notch contour and displaying the dynamic wing badge on the primary display.
_Avoid_: MiniNotch, SmallPill, IdleCapsule

**ExtendedMenuBar**:
The expanded state of an island panel rendering the zero-fallback mirrored bitmap icons of all overflow items.
_Avoid_: ExpandedIsland, DropdownBar, OverflowMenu

**ExternalStealth**:
The folded idle state of the external panel on a flat external display: fully invisible and click-through, so the native menu bar stays pristine and nothing is intercepted. Replaced the abolished flat-docked shelf concept.
_Avoid_: HiddenMode, DormantShelf, FloatingShelf

**FocusFollowing**:
The viewport ownership model where panel ownership is decided solely by screen focus: the primary panel never leaves the notch, and the external panel reveals in place and fades out in place. Replaced the abolished "Viewport Leasing" model.
_Avoid_: ViewportLease, ViewportMigration, PanelRelocation

**NativeMenuAnchor**:
The original physical coordinate of a MenuBarItem where native dropdown menus pop up upon synthetic event dispatch.
_Avoid_: FloatingMenuAnchor, DetachedMenu

**FullScreenStealth**:
The dormant state where an island panel fades out and turns click-through in full-screen spaces, to prevent obscuring user content.
_Avoid_: FullScreenDisabled, HiddenInFullScreen

**TopEdgeHotZone**:
The physical screen top boundary hot-zone that triggers the smooth wake-up or on-demand expansion of an island panel.
_Avoid_: WakeUpTriggerLine, TopHoverMargin

**SmartHeartbeat**:
The three-tier energy schedule driving menu bar scanning: `Dormant` (timers fully suspended, no CPU cost), `Armed` (a single incremental pre-warm on top-edge approach, with a timeout guard), and `Active` (a periodic heartbeat while any panel is expanded, with a short cooldown after collapse).
_Avoid_: PollingLoop, RefreshTimer, IdleScan

**CustomItemOrder**:
The persisted user-defined ordering of status items. Ordered keys come first; unlisted items follow in physical coordinate order. Edited by dragging icons in the expanded island.
_Avoid_: SortIndex, PriorityList, ManualRank

**ReorderableIconRow**:
The expanded-island view that supports fluid drag-and-drop reordering of mirrored icons, committing the new order atomically to the custom item order.
_Avoid_: DragList, SortableGrid, ManualLayoutRow
