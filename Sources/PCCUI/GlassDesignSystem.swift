import SwiftUI

/// Shared "instrument panel" design system for every `PCCUI` screen: bordered,
/// solid-filled panels — a console/readout aesthetic, not soft frosted
/// glass — plus a small status-signal vocabulary (`PanelStatus`/`StatusDot`)
/// every panel header uses to say "nominal," "needs you," or "running" at a
/// glance, the same way a real instrument panel uses colored lamps rather
/// than making you read every gauge to know what needs attention.
///
/// Still named `Glass*` (`GlassCard`, `glassRows()`, …) even though the
/// visual language has moved on from blur-and-shadow glass to bordered
/// panels — renaming the public API would mean touching every screen in
/// this package for a purely cosmetic reason. The names are legacy; the
/// tokens underneath them are current.
///
/// Centralized here so every screen — CRUD `List`s, `Form` create/edit
/// sheets, and the Overview dashboard alike — reads as one consistent
/// visual system instead of each screen inventing its own surface, corner
/// radius, and color values.
///
/// Colors here key off `@Environment(\.colorScheme)` rather than system
/// dynamic colors (`NSColor`/`UIColor`) — the app has its own explicit
/// Light/Dark switch (`PCCDesktop`'s sidebar Settings section, via
/// `.preferredColorScheme`), not just system-appearance-following, and a
/// dynamic system color isn't guaranteed to repaint from a
/// `.preferredColorScheme` override applied several view-levels up the way
/// reading `colorScheme` directly and picking an explicit color is.
public enum GlassStyle {
    /// Corner radius for a single `List`/`Form` row's panel background.
    public static let rowCornerRadius: CGFloat = 10
    /// Corner radius for a standalone `GlassCard` widget — slightly larger
    /// than a row's, but a tight bezel rather than the fully-rounded, soft
    /// panel this system used before switching to the instrument-panel
    /// look.
    public static let cardCornerRadius: CGFloat = 14
    /// Corner radius for a compact interactive control chip
    /// (`FormControls.swift`'s `PCCDateRangeControl`/boxed `PCCMenuPicker`).
    public static let controlCornerRadius: CGFloat = 8

    // MARK: - Panel surface

    /// The screen backdrop every panel sits on.
    public static func panelVoid(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x0B0D10) : Color(hex: 0xF5F7F8)
    }

    /// A panel's own solid fill — no material blur. A bordered, solid
    /// surface reads as instrumentation; blur-and-shadow reads as soft
    /// consumer-app glass, which is exactly the look this redesign moved
    /// away from.
    public static func panelSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x14171C) : .white
    }

    /// The hairline used for panel borders, dividers, and chart gridlines
    /// — the structural "etched line" language that replaces this system's
    /// old soft shadows.
    public static func panelLine(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x262B33) : Color(hex: 0xD7DCE1)
    }

    // MARK: - Signal colors

    /// This system's one "primary data" accent — what a hero readout (Net
    /// Worth, the Timer's elapsed time) is colored in. Distinct from the
    /// red/amber/green status vocabulary below, which is reserved for
    /// signaling urgency rather than marking "this is the important
    /// number."
    public static func signalCyan(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x5EEAD4) : Color(hex: 0x0F9488)
    }

    public static func signalGreen(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x34D399) : Color(hex: 0x0F9960)
    }

    public static func signalAmber(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0xFFB454) : Color(hex: 0xB5730A)
    }

    public static func signalRed(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0xFF5C5C) : Color(hex: 0xC6362E)
    }
}

/// One panel's status, surfaced as a small colored `StatusDot` in its
/// header — this design system's signature device. Not decoration: every
/// use computes this from the same real data the panel itself shows (e.g.
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

    public func color(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .nominal: return GlassStyle.signalGreen(for: colorScheme)
        case .attention: return GlassStyle.signalAmber(for: colorScheme)
        case .critical: return GlassStyle.signalRed(for: colorScheme)
        case .active: return GlassStyle.signalCyan(for: colorScheme)
        case .idle: return colorScheme == .dark ? Color(hex: 0x3A3F47) : Color(hex: 0xC4CBD1)
        }
    }
}

/// A small glowing indicator lamp — every panel header's status signal.
public struct StatusDot: View {
    private let status: PanelStatus

    @Environment(\.colorScheme) private var colorScheme

    public init(_ status: PanelStatus) {
        self.status = status
    }

    public var body: some View {
        let color = status.color(for: colorScheme)
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(status == .idle ? 0 : 0.75), radius: 3)
    }
}

extension Font {
    /// This system's one deliberate typographic signature: a monospaced
    /// "digital readout" treatment for hero numbers — Net Worth, the
    /// Timer's elapsed time, completion percentages — distinct from the
    /// system font every other value in this package uses for ordinary
    /// labels and body text.
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
/// fill (explicit per-mode color; see this file's top-level doc comment
/// for why it's explicit rather than a system dynamic color) with a faint
/// glow from the top, like a console just powered on, rather than the
/// diagonal color wash this system used before.
public struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            GlassStyle.panelVoid(for: colorScheme)
            RadialGradient(
                colors: [GlassStyle.signalCyan(for: colorScheme).opacity(glowOpacity), .clear],
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

/// The one surface shape every panel in this system uses — a solid
/// panel-fill rounded rectangle with a hairline border. Used directly by
/// `GlassCard` (a standalone widget) and, as a `List`/`Form` row
/// background, by `View.glassRows()` below.
private struct GlassSurface: View {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(GlassStyle.panelSurface(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(GlassStyle.panelLine(for: colorScheme), lineWidth: 1)
            )
    }
}

/// Wraps `content` in a standalone panel — `OverviewView`'s dashboard is
/// built entirely out of these, one per widget (Finances, Work,
/// Productivity), and `TimerView` uses the same shape for its own cards.
/// Fills the full width it's given (`maxWidth: .infinity`) and grows past
/// `minHeight` if its content needs more (`maxHeight: .infinity`), rather
/// than shrinking to its content's own size — `LazyVGrid` does *not*
/// stretch a short cell to match its taller row-mates on its own (a common,
/// easy-to-miss gap in its layout, unlike the newer `Grid`), so a light
/// widget like Timer needs an explicit floor to avoid visibly leaving a gap
/// of bare backdrop around a smaller box.
public struct GlassCard<Content: View>: View {
    /// Every dashboard widget shares this floor so the grid reads as evenly
    /// sized tiles rather than whichever height each widget's own content
    /// happens to need. `public` only because a `public` initializer's
    /// default argument must be able to reference it, not because callers
    /// are expected to read it directly — pass `minHeight:` to override.
    public static var defaultMinHeight: CGFloat { 220 }

    private let content: Content
    private let minHeight: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    public init(minHeight: CGFloat = GlassCard.defaultMinHeight, @ViewBuilder content: () -> Content) {
        self.minHeight = minHeight
        self.content = content()
    }

    public var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
            .background(GlassSurface(cornerRadius: GlassStyle.cardCornerRadius))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.06), radius: 8, x: 0, y: 3)
    }
}

extension View {
    /// Applies the app-wide backdrop behind a `NavigationStack`'s root
    /// `List`/`Form`, and hides that container's own opaque scroll
    /// background so the backdrop — and, per-row, the panel fill from
    /// `glassRows()` — actually shows through. Every screen's root
    /// `List`/`Form`, and every `Form`-based create/edit sheet, calls this
    /// once on itself.
    public func glassScreenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
    }

    /// The row-level counterpart: a panel-fill row background and a hidden
    /// separator, so rows read as small panels sitting on the backdrop
    /// `glassScreenBackground()` provides, instead of plain opaque rows.
    /// `.listRowBackground`/`.listRowSeparator` cascade from whatever
    /// they're attached to down to every row inside it, so this is meant
    /// to be called once per `Section` (or bare `ForEach`) — not once per
    /// individual row.
    public func glassRows() -> some View {
        self
            .listRowBackground(
                GlassSurface(cornerRadius: GlassStyle.rowCornerRadius)
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
