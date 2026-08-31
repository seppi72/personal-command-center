import SwiftUI

/// Shared "instrument panel" chassis for every `PCCUI` screen: bordered,
/// solid-filled panels — a console/readout aesthetic, not soft frosted
/// glass — plus a small status-signal vocabulary (`PanelStatus`/
/// `StatusDot`) every panel header uses to say "nominal," "needs you," or
/// "running" at a glance, the same way a real instrument panel uses
/// colored lamps rather than making you read every gauge to know what
/// needs attention.
///
/// Was `GlassDesignSystem.swift` — renamed once the design direction moved
/// past "one shared frosted-glass look" into "one shared *chassis*, many
/// per-screen *themes*" (see `ScreenTheme` below), which made the old
/// `Glass*` names doubly stale.
///
/// Splits what every screen shares from what's free to vary per screen:
/// - **This file's `PCCChassis` enum** — structural constants (corner
///   radii, the hard minimum outer margin) and the shape-level views
///   (`PanelCard`, `StatusDot`, `.panelRows()`) that give every screen the
///   same *device* for showing a panel and a status signal, regardless of
///   that screen's own colors.
/// - **`ScreenTheme`** — the *material*: panel surface/void/line colors
///   and the signal-color palette a screen's `StatusDot`s and readouts
///   resolve against. Injected per screen via
///   `\.screenTheme`/`.screenTheme(_:)`, defaulting to `.default` (today's
///   one shared cyan/green/amber/red palette) so every screen not yet
///   carrying its own distinct vibe renders exactly as before without
///   having to opt into anything.
///
/// Colors here key off `@Environment(\.colorScheme)` rather than system
/// dynamic colors (`NSColor`/`UIColor`) — the app has its own explicit
/// Light/Dark switch (`PCCDesktop`'s sidebar Settings section, via
/// `.preferredColorScheme`), not just system-appearance-following, and a
/// dynamic system color isn't guaranteed to repaint from a
/// `.preferredColorScheme` override applied several view-levels up the way
/// reading `colorScheme` directly and picking an explicit color is.
public enum PCCChassis {
    /// Corner radius for a single `List`/`Form` row's panel background.
    public static let rowCornerRadius: CGFloat = 10
    /// Corner radius for a standalone `PanelCard` widget — slightly larger
    /// than a row's, but a tight bezel rather than a fully-rounded, soft
    /// panel.
    public static let cardCornerRadius: CGFloat = 14
    /// Corner radius for a compact interactive control chip
    /// (`FormControls.swift`'s `PCCDateRangeControl`/boxed `PCCMenuPicker`).
    public static let controlCornerRadius: CGFloat = 8

    /// The hard minimum breathing room between any panel and a window or
    /// sidebar edge. Bumped from the previous ad hoc 16pt screen padding —
    /// which read as cards sitting flush against the window edge, since
    /// there's no sidebar-gray on that side to visually register the gap
    /// — to a value generous enough to read as deliberate spacing rather
    /// than "ran out of room." Every screen's own outer padding should be
    /// at least this, not a smaller value chosen per screen.
    public static let outerMargin: CGFloat = 24
}

/// A screen's own palette: the material every panel, `StatusDot`, and
/// signal-colored readout on that screen resolves its colors against.
/// Every color is a function of `ColorScheme` rather than a fixed `Color`
/// — same reasoning as this file's own top-level doc comment — so a theme
/// stays correct across the app's explicit Light/Dark switch.
///
/// One value type rather than a protocol or subclass: a theme is just
/// data (a bundle of color-resolvers), so a new per-screen vibe is a new
/// `ScreenTheme` literal, not a new type. Inject a screen's theme once at
/// its own root via `.screenTheme(_:)`; every chassis view underneath
/// (`PanelCard`, `StatusDot`, `.panelRows()`, and any shared control like
/// `SyncStatusBadge`) reads it back via `\.screenTheme` and re-skins to
/// match, so dropping a shared control into a themed screen doesn't
/// require that control to know about the theme by name.
public struct ScreenTheme: Sendable {
    public var panelVoid: @Sendable (ColorScheme) -> Color
    public var panelSurface: @Sendable (ColorScheme) -> Color
    public var panelLine: @Sendable (ColorScheme) -> Color
    /// This theme's one "primary data" accent — what a hero readout (Net
    /// Worth, the Timer's elapsed time) is colored in. Distinct from the
    /// signal colors below, which are reserved for signaling urgency
    /// rather than marking "this is the important number."
    public var accent: @Sendable (ColorScheme) -> Color
    public var signalGreen: @Sendable (ColorScheme) -> Color
    public var signalAmber: @Sendable (ColorScheme) -> Color
    public var signalRed: @Sendable (ColorScheme) -> Color

    public init(
        panelVoid: @escaping @Sendable (ColorScheme) -> Color,
        panelSurface: @escaping @Sendable (ColorScheme) -> Color,
        panelLine: @escaping @Sendable (ColorScheme) -> Color,
        accent: @escaping @Sendable (ColorScheme) -> Color,
        signalGreen: @escaping @Sendable (ColorScheme) -> Color,
        signalAmber: @escaping @Sendable (ColorScheme) -> Color,
        signalRed: @escaping @Sendable (ColorScheme) -> Color
    ) {
        self.panelVoid = panelVoid
        self.panelSurface = panelSurface
        self.panelLine = panelLine
        self.accent = accent
        self.signalGreen = signalGreen
        self.signalAmber = signalAmber
        self.signalRed = signalRed
    }

    /// Today's one shared instrument-panel palette — every screen not yet
    /// carrying its own distinct vibe uses this, unchanged from what was
    /// previously the global `GlassStyle`.
    public static let `default` = ScreenTheme(
        panelVoid: { $0 == .dark ? Color(hex: 0x0B0D10) : Color(hex: 0xF5F7F8) },
        panelSurface: { $0 == .dark ? Color(hex: 0x14171C) : .white },
        panelLine: { $0 == .dark ? Color(hex: 0x262B33) : Color(hex: 0xD7DCE1) },
        accent: { $0 == .dark ? Color(hex: 0x5EEAD4) : Color(hex: 0x0F9488) },
        signalGreen: { $0 == .dark ? Color(hex: 0x34D399) : Color(hex: 0x0F9960) },
        signalAmber: { $0 == .dark ? Color(hex: 0xFFB454) : Color(hex: 0xB5730A) },
        signalRed: { $0 == .dark ? Color(hex: 0xFF5C5C) : Color(hex: 0xC6362E) }
    )
}

private struct ScreenThemeKey: EnvironmentKey {
    static let defaultValue: ScreenTheme = .default
}

extension EnvironmentValues {
    public var screenTheme: ScreenTheme {
        get { self[ScreenThemeKey.self] }
        set { self[ScreenThemeKey.self] = newValue }
    }
}

extension View {
    /// Injects `theme` for this screen and everything under it — call once
    /// at a screen's own root (its `NavigationStack`, typically). Screens
    /// that don't call this at all get `ScreenTheme.default`, which is why
    /// porting a screen onto this chassis is zero visual change until it
    /// explicitly opts into its own theme.
    ///
    /// **Call this from a screen's public wrapper view, not from the same
    /// struct that reads `@Environment(\.screenTheme)` to build its own
    /// body.** A view's environment modifiers only affect the subtree
    /// below them — they never reach back into that same view's own body
    /// computation. A screen's public `View` (the thing `PCCDesktop`
    /// instantiates) should do nothing but
    /// `SomeContent(...).screenTheme(.someTheme)`; the actual panels,
    /// colors, and `@Environment(\.screenTheme)` reads belong in a
    /// separate `SomeContent` struct underneath it. Skipping this split —
    /// applying `.screenTheme()` and reading `\.screenTheme` in the same
    /// struct — silently keeps every color computed in that struct's own
    /// body on `ScreenTheme.default`, no matter what's passed here.
    /// (`FinancesReportingView`/`FinancesReportingContent` is the worked
    /// example: caught when the first build rendered the shared cyan
    /// instead of the intended gold.)
    public func screenTheme(_ theme: ScreenTheme) -> some View {
        environment(\.screenTheme, theme)
    }
}

/// One panel's status, surfaced as a small colored `StatusDot` in its
/// header — this chassis's signature device. Not decoration: every use
/// computes this from the same real data the panel itself shows (e.g.
/// `OverviewViewModel.workStatus` goes `.critical` exactly when
/// `tasksOverdue` isn't empty), so the dot is a second, glanceable read of
/// a fact the panel's own content already states in full.
public enum PanelStatus: Equatable {
    /// Nothing needs attention.
    case nominal
    /// Worth a look, not urgent (e.g. something due today).
    case attention
    /// Needs the owner now (e.g. something overdue, a negative balance).
    case critical
    /// A live, in-progress state rather than an urgency signal (e.g. the
    /// Timer currently running) — reuses the same dot language for "this
    /// panel is doing something" rather than "this panel needs you."
    case active
    /// No signal to show — a dim, inert dot rather than omitting it, so
    /// every panel header keeps the same layout whether or not it has
    /// something to report.
    case idle

    public func color(for colorScheme: ColorScheme, theme: ScreenTheme) -> Color {
        switch self {
        case .nominal: return theme.signalGreen(colorScheme)
        case .attention: return theme.signalAmber(colorScheme)
        case .critical: return theme.signalRed(colorScheme)
        case .active: return theme.accent(colorScheme)
        // A fixed neutral rather than anything theme-derived — "off" reads
        // the same dim gray regardless of which screen's palette is
        // active, the same way a real instrument panel's unlit lamps all
        // look alike no matter what the lit ones signal.
        case .idle: return colorScheme == .dark ? Color(hex: 0x3A3F47) : Color(hex: 0xC4CBD1)
        }
    }
}

/// A small glowing indicator lamp — every panel header's status signal.
public struct StatusDot: View {
    private let status: PanelStatus

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    public init(_ status: PanelStatus) {
        self.status = status
    }

    public var body: some View {
        let color = status.color(for: colorScheme, theme: theme)
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(status == .idle ? 0 : 0.75), radius: 3)
    }
}

extension Font {
    /// This chassis's one deliberate typographic signature: a monospaced
    /// "digital readout" treatment for hero numbers — Net Worth, the
    /// Timer's elapsed time, completion percentages — distinct from the
    /// system font every other value in this package uses for ordinary
    /// labels and body text. Kept as a plain static font rather than part
    /// of `ScreenTheme`: no screen has needed a different readout typeface
    /// yet, and a screen that wants one can just reach for a different
    /// `Font` call directly in its own view code.
    public static func pccReadout(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// A panel's own nameplate treatment: small, uppercase, letter-spaced,
    /// and deliberately quiet — a `pccReadout` number sitting near it is
    /// what's meant to carry the visual weight, not this label.
    public func pccPanelLabel() -> some View {
        font(.system(size: 11, weight: .semibold))
            .tracking(1.4)
            .textCase(.uppercase)
    }
}

/// The ambient backdrop every screen sits on top of — a solid panel-void
/// fill with a faint glow from the top, like a console just powered on,
/// rather than a diagonal color wash.
public struct PanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    public init() {}

    public var body: some View {
        ZStack {
            theme.panelVoid(colorScheme)
            RadialGradient(
                colors: [theme.accent(colorScheme).opacity(glowOpacity), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    /// Dialed down further in dark mode so the glow doesn't wash out an
    /// already-dark base.
    private var glowOpacity: Double {
        colorScheme == .dark ? 0.05 : 0.035
    }
}

/// The one surface shape every panel in this chassis uses — a solid
/// panel-fill rounded rectangle with a hairline border. Used directly by
/// `PanelCard` (a standalone widget) and, as a `List`/`Form` row
/// background, by `View.panelRows()` below.
private struct PanelSurface: View {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(theme.panelSurface(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(theme.panelLine(colorScheme), lineWidth: 1)
            )
    }
}

/// Wraps `content` in a standalone panel — `OverviewView`'s dashboard is
/// built entirely out of these, one per widget (Finances, Work,
/// Productivity), and `TimeEntriesView` uses the same shape for its own
/// hero timer cards.
/// Fills the full width it's given (`maxWidth: .infinity`) and grows past
/// `minHeight` if its content needs more (`maxHeight: .infinity`), rather
/// than shrinking to its content's own size — `LazyVGrid` does *not*
/// stretch a short cell to match its taller row-mates on its own (a common,
/// easy-to-miss gap in its layout, unlike the newer `Grid`), so a light
/// widget like Timer needs an explicit floor to avoid visibly leaving a gap
/// of bare backdrop around a smaller box.
public struct PanelCard<Content: View>: View {
    /// Every dashboard widget shares this floor so the grid reads as evenly
    /// sized tiles rather than whichever height each widget's own content
    /// happens to need. `public` only because a `public` initializer's
    /// default argument must be able to reference it, not because callers
    /// are expected to read it directly — pass `minHeight:` to override.
    public static var defaultMinHeight: CGFloat { 220 }

    private let content: Content
    private let minHeight: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    public init(minHeight: CGFloat = PanelCard.defaultMinHeight, @ViewBuilder content: () -> Content) {
        self.minHeight = minHeight
        self.content = content()
    }

    public var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
            .background(PanelSurface(cornerRadius: PCCChassis.cardCornerRadius))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.06), radius: 8, x: 0, y: 3)
    }
}

extension View {
    /// Applies the app-wide backdrop behind a `NavigationStack`'s root
    /// `List`/`Form`, and hides that container's own opaque scroll
    /// background so the backdrop — and, per-row, the panel fill from
    /// `panelRows()` — actually shows through. Every screen's root
    /// `List`/`Form`, and every `Form`-based create/edit sheet, calls this
    /// once on itself.
    public func panelScreenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(PanelBackground())
    }

    /// The row-level counterpart: a panel-fill row background and a hidden
    /// separator, so rows read as small panels sitting on the backdrop
    /// `panelScreenBackground()` provides, instead of plain opaque rows.
    /// `.listRowBackground`/`.listRowSeparator` cascade from whatever
    /// they're attached to down to every row inside it, so this is meant
    /// to be called once per `Section` (or bare `ForEach`) — not once per
    /// individual row.
    public func panelRows() -> some View {
        self
            .listRowBackground(
                PanelSurface(cornerRadius: PCCChassis.rowCornerRadius)
                    .padding(.vertical, 2)
            )
            .listRowSeparator(.hidden)
    }
}

extension Color {
    /// A `0xRRGGBB` literal initializer — every named token above is
    /// defined this way rather than as an asset-catalog color, since this
    /// package has no asset catalog of its own (it's a plain SPM library
    /// target, not an app target; see this repo's README for why).
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
