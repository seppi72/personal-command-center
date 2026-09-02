import SwiftUI

/// Shared chassis for every `PCCUI` screen — every surface a screen can be
/// built out of, plus the small status-signal vocabulary (`PanelStatus`/
/// `StatusDot`) every screen's header strip uses to say "nominal," "needs
/// you," or "running" at a glance, the same way a real instrument panel
/// uses colored lamps rather than making you read every gauge to know what
/// needs attention.
///
/// Two surface families live here, mid-migration (issue #65):
/// - **Liquid Glass** (`GlassBubble`, `GlassScreenBackground`,
///   `ScreenTheme.liquidGlass`) — genuine `Material`-backed bubbles on a
///   plain white/black ground with a faint dot grid. This is where every
///   screen is headed; `AccountsView` and `CategoriesView` are there.
/// - **The console panel** (`PanelCard`, `PanelBackground`,
///   `.panelRows()`, `.panelScreenBackground()`) — bordered, solid-filled
///   panels, from the earlier instrument-panel phase. Still what every
///   not-yet-converted screen renders, and what create/edit sheets use on
///   converted screens too, since a `Form`'s native controls don't read as
///   glass however they're dressed.
///
/// Was `GlassDesignSystem.swift` — renamed during the instrument-panel
/// phase, when the shared look genuinely wasn't glass at all; the name
/// still holds, since what's shared is now *two* surface families and the
/// status vocabulary rather than one look.
///
/// Splits what every screen shares from what's free to vary per screen:
/// - **This file's `PCCChassis` enum, plus `GlassBubbleStyle`** —
///   structural constants (corner radii, specular geometry, the hard
///   minimum outer margin) and the shape-level views (`PanelCard`,
///   `GlassBubble`, `StatusDot`, `.panelRows()`) that give every screen the
///   same *devices*, regardless of that screen's own colors. `PCCChassis`
///   holds the console family's constants and `GlassBubbleStyle` the
///   glass family's, rather than one flat namespace where
///   `rowCornerRadius` (10) and a glass bubble's radius (30) would sit
///   side by side meaning unrelated things.
/// - **`ScreenTheme`** — the *material*: panel surface/void/line colors
///   and the signal-color palette a screen's `StatusDot`s and readouts
///   resolve against. Injected per screen via
///   `\.screenTheme`/`.screenTheme(_:)`, defaulting to `.default` (the
///   console family's cyan/green/amber/red palette) so every screen not yet
///   converted renders exactly as before without having to opt into
///   anything. A glass bubble's white tint is the one deliberate exception
///   — see `GlassBubble` for why glass takes its color from what's behind
///   it rather than from the palette.
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

extension ScreenTheme {
    /// The one shared Liquid Glass palette — plain white (Light) / plain
    /// black (Dark) ground with no color in the background at all, and a
    /// green/red pair that is this system's real accent because the figure
    /// a glass bubble carries (a balance, an amount spent) *is* the point
    /// of the screen it sits on.
    ///
    /// Was two near-identical `fileprivate` literals, `AccountsView`'s
    /// `liquidGlass` and `CategoriesView`'s `categoryGlass`, back when each
    /// screen genuinely owned its own vibe. Under the uniform system (issue
    /// #65) they no longer differ by design, so they collapse into this one
    /// public value. The two literals disagreed on exactly one channel —
    /// dark-mode `signalRed`, `0xE8695A` on Accounts against `0xE2776A` on
    /// Categories — and this takes Categories' value, per owner's
    /// direction, so Accounts' dark-mode negative balances shift by that
    /// one imperceptible step rather than the system carrying two reds
    /// that mean the same thing.
    ///
    /// `panelSurface`/`panelLine` still matter even though a glass bubble
    /// draws its own Material-backed fill: the chassis's opaque
    /// `PanelSurface` is what create/edit sheets (`AccountFormSheet`,
    /// `CategoryFormSheet`) keep using, since a `Form`'s native controls
    /// don't read as glass however they're dressed, and `panelLine` is the
    /// hairline rim every bubble strokes itself with.
    public static let liquidGlass = ScreenTheme(
        panelVoid: { $0 == .dark ? Color.black : Color.white },
        panelSurface: { $0 == .dark ? Color(hex: 0x121212) : Color(hex: 0xF7F7F7) },
        panelLine: { $0 == .dark ? Color(hex: 0x2A2A2A) : Color(hex: 0xE3E3E3) },
        accent: { $0 == .dark ? Color(hex: 0x45C989) : Color(hex: 0x157A4C) },
        signalGreen: { $0 == .dark ? Color(hex: 0x45C989) : Color(hex: 0x157A4C) },
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: { $0 == .dark ? Color(hex: 0xE2776A) : Color(hex: 0xB23226) }
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

// MARK: - Liquid Glass

/// The ground every Liquid Glass screen sits on: a hairline dot grid,
/// almost invisible, over the theme's plain white/black void — enough
/// texture for a bubble's `Material` blur to lens against, without reading
/// as a "background" the way a colored gradient mesh would (the direction
/// this replaced, per direct product feedback). Canvas-drawn rather than a
/// repeating SwiftUI view, so the grid costs one draw call rather than one
/// view per dot.
///
/// The glass counterpart to `PanelBackground`, which stays for screens
/// still on the older console chassis: apply this behind a screen's
/// content (`.background(GlassScreenBackground())`), not in place of
/// `panelScreenBackground()` on a `Form`-based sheet.
public struct GlassScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    /// Distance between neighboring dots, in points, both axes.
    private static let spacing: CGFloat = 22

    public init() {}

    public var body: some View {
        Canvas { context, size in
            let dotColor = theme.panelLine(colorScheme).opacity(0.8)
            var x: CGFloat = Self.spacing / 2
            while x < size.width {
                var y: CGFloat = Self.spacing / 2
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1)),
                        with: .color(dotColor)
                    )
                    y += Self.spacing
                }
                x += Self.spacing
            }
        }
        .background(theme.panelVoid(colorScheme))
    }
}

/// The dimensions one glass bubble is cut to — everything that
/// legitimately differs between a full-width row bubble and a smaller grid
/// cell, and nothing that doesn't. The material, the tint, the rim color
/// and the highlight's *shape* are fixed by `GlassBubble` itself; only
/// size-dependent geometry lives here, so a bubble can't accidentally be
/// given a different kind of glass, just a different size of it.
///
/// The two presets below are the whole vocabulary — the memberwise
/// initializer is deliberately not `public`, since a third size would mean
/// some screen's *layout* wants rethinking, not the glass. Named
/// `.fullWidth`/`.gridCell` rather than `row`/`card` so they can't be read
/// as glass counterparts of `PCCChassis.rowCornerRadius`/
/// `cardCornerRadius`, which are the console chassis's own (much tighter)
/// panel radii.
public struct GlassBubbleStyle: Sendable, Equatable {
    /// The blurred highlight arcing across a bubble's top, like light
    /// catching a curved surface. Its three numbers only ever travel
    /// together, so they're one value rather than three loose fields.
    public struct Specular: Sendable, Equatable {
        /// The highlight's ellipse. Its radial gradient fades out over
        /// exactly this height, so the highlight always dies at its own
        /// edge rather than being clipped mid-falloff.
        public let size: CGSize
        /// Where that ellipse sits relative to the bubble's center — up
        /// and to the left on both presets, so light reads as coming from
        /// one consistent direction app-wide.
        public let offset: CGSize
        public let blur: CGFloat

        init(size: CGSize, offset: CGSize, blur: CGFloat) {
            self.size = size
            self.offset = offset
            self.blur = blur
        }
    }

    public let cornerRadius: CGFloat
    public let specular: Specular
    public let shadowRadius: CGFloat
    public let shadowOffsetY: CGFloat
    /// Heavier in Dark Mode, where a soft shadow is the only thing
    /// separating a dim bubble from a black ground.
    public let shadowOpacityDark: Double
    public let shadowOpacityLight: Double

    init(
        cornerRadius: CGFloat,
        specular: Specular,
        shadowRadius: CGFloat,
        shadowOffsetY: CGFloat,
        shadowOpacityDark: Double,
        shadowOpacityLight: Double
    ) {
        self.cornerRadius = cornerRadius
        self.specular = specular
        self.shadowRadius = shadowRadius
        self.shadowOffsetY = shadowOffsetY
        self.shadowOpacityDark = shadowOpacityDark
        self.shadowOpacityLight = shadowOpacityLight
    }

    /// A full-width list row's bubble — `AccountsView`'s account rows.
    public static let fullWidth = GlassBubbleStyle(
        cornerRadius: 30,
        specular: Specular(
            size: CGSize(width: 170, height: 90),
            offset: CGSize(width: -60, height: -46),
            blur: 10
        ),
        shadowRadius: 20,
        shadowOffsetY: 10,
        shadowOpacityDark: 0.5,
        shadowOpacityLight: 0.08
    )

    /// A grid cell's bubble — `CategoriesView`'s category cards. Smaller
    /// radius, highlight and shadow than `.fullWidth`, in proportion to a
    /// cell that's roughly a third of the width.
    public static let gridCell = GlassBubbleStyle(
        cornerRadius: 26,
        specular: Specular(
            size: CGSize(width: 130, height: 70),
            offset: CGSize(width: -40, height: -36),
            blur: 8
        ),
        shadowRadius: 16,
        shadowOffsetY: 8,
        shadowOpacityDark: 0.4,
        shadowOpacityLight: 0.08
    )
}

/// The one glass surface every Liquid Glass screen's bubbles are drawn
/// with: a genuine `Material` fill (real OS-level backdrop blur and
/// vibrancy, not a hand-rolled translucent rectangle), a soft white tint
/// over it, a blurred specular highlight, and a hairline rim in the
/// theme's `panelLine`. The glass counterpart to `PanelSurface`, which the
/// console chassis's opaque `PanelCard`/`panelRows()` still use.
///
/// Public, and a surface rather than a container, because the content that
/// sits on glass differs wildly per screen (a row's icon/name/balance, a
/// cell's stacked label and total) while the glass itself must not. Use it
/// as a background — `content.padding(...).background(GlassBubble())` — or
/// via `View.glassBubble(_:)` just below.
///
/// The white-based tint is deliberate and *not* theme-derived: like real
/// glass, the color comes from whatever is behind it — here the
/// `Material`'s own light/dark vibrancy — rather than from the app's
/// palette. The rim is the one part that does read the theme, since a
/// hairline edge has to sit against that screen's ground to be visible at
/// all.
public struct GlassBubble: View {
    private let style: GlassBubbleStyle

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    public init(_ style: GlassBubbleStyle = .fullWidth) {
        self.style = style
    }

    /// The tint laid over the `Material`, and the rim stroked around it.
    /// Both are reachable beyond `body` so a screen's own non-rectangular
    /// glass prop — `AccountsView`'s round type-icon well — is cut from the
    /// same glass as the bubble it sits inside, instead of re-deriving
    /// these opacities by eye. `internal`: every caller is a screen in this
    /// package, and nothing outside it should be hand-rolling glass.
    static func tint(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.72),
                colorScheme == .dark ? Color.white.opacity(0.02) : Color.white.opacity(0.24),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func rimColor(_ theme: ScreenTheme, _ colorScheme: ColorScheme) -> Color {
        theme.panelLine(colorScheme).opacity(0.7)
    }

    static let rimWidth: CGFloat = 1

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Self.tint(for: colorScheme)))
            .overlay(specularHighlight)
            .overlay(shape.strokeBorder(Self.rimColor(theme, colorScheme), lineWidth: Self.rimWidth))
            .clipShape(shape)
            .shadow(
                color: .black.opacity(colorScheme == .dark ? style.shadowOpacityDark : style.shadowOpacityLight),
                radius: style.shadowRadius,
                x: 0,
                y: style.shadowOffsetY
            )
    }

    private var specularHighlight: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(colorScheme == .dark ? 0.22 : 0.55), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: style.specular.size.height
                )
            )
            .frame(width: style.specular.size.width, height: style.specular.size.height)
            .rotationEffect(.degrees(-12))
            .offset(x: style.specular.offset.width, y: style.specular.offset.height)
            .blur(radius: style.specular.blur)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Puts this content on a `GlassBubble` — the glass counterpart to
    /// `panelRows()`, for content laid out by hand in a `ScrollView` rather
    /// than by a `List`.
    public func glassBubble(_ style: GlassBubbleStyle = .fullWidth) -> some View {
        background(GlassBubble(style))
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
