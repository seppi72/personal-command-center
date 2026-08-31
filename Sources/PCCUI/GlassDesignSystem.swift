import SwiftUI

/// Shared glassmorphism design system for every `PCCUI` screen: a soft,
/// mostly-white frosted-glass backdrop plus translucent surfaces for both
/// `List`/`Form` rows and standalone "widget" cards (`OverviewView`'s
/// dashboard grid) — modeled on a clean white-glass reference (a pale,
/// barely-tinted backdrop behind large white frosted cards with soft
/// shadows and no heavy color wash), not a colorful/tinted glass look.
/// Centralized here so every screen — CRUD `List`s, `Form` create/edit
/// sheets, and the Overview dashboard alike — reads as one consistent
/// visual system instead of each screen inventing its own translucency,
/// corner radius, and shadow values.
///
/// Colors here key off `@Environment(\.colorScheme)` rather than system
/// dynamic colors (`NSColor`/`UIColor`) — the app has its own explicit
/// Light/Dark switch (`PCCDesktop`'s sidebar Settings section, via
/// `.preferredColorScheme`), not just system-appearance-following, and a
/// dynamic system color isn't guaranteed to repaint from a
/// `.preferredColorScheme` override applied several view-levels up the way
/// reading `colorScheme` directly and picking an explicit color is.
public enum GlassStyle {
    /// Corner radius for a single `List`/`Form` row's glass background.
    public static let rowCornerRadius: CGFloat = 14
    /// Corner radius for a standalone `GlassCard` widget — larger than a
    /// row's, matching the reference's big, soft-cornered panel.
    public static let cardCornerRadius: CGFloat = 24
    /// Corner radius for a compact interactive control chip
    /// (`FormControls.swift`'s `PCCDateRangeControl`/boxed `PCCMenuPicker`)
    /// — smaller than either surface radius above, since a small inline
    /// control reads oddly with a card-sized corner.
    public static let controlCornerRadius: CGFloat = 8
}

/// The ambient backdrop every screen sits on top of — an explicit white
/// (light) or near-black (dark) base, with only a faint, mostly-monochrome
/// pale-blue wash (no accent-color/purple tinting) so the frosted cards on
/// top of it read as clear glass, not colored glass. Still gives
/// `.ultraThinMaterial` enough texture behind it to visibly blur.
public struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            baseColor
            LinearGradient(
                colors: [
                    Color.blue.opacity(washOpacity.0),
                    Color.clear,
                    Color.blue.opacity(washOpacity.1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    /// Explicit white/near-black rather than a system dynamic color — see
    /// this file's top-level doc comment for why. Near-black rather than
    /// pure black: a real dark-mode surface is usually a soft dark gray.
    private var baseColor: Color {
        colorScheme == .dark ? Color(white: 0.09) : Color.white
    }

    /// Dialed down further in dark mode so the wash doesn't muddy the
    /// already-dark base.
    private var washOpacity: (Double, Double) {
        colorScheme == .dark ? (0.05, 0.03) : (0.08, 0.05)
    }
}

/// The one translucent surface shape every glass element in this package
/// uses — a rounded rectangle filled with `.ultraThinMaterial`, a white
/// tint on top of it (light enough in *both* modes to read as clear glass —
/// visibly see-through, not a solid panel — rather than heavy in light mode
/// and faint in dark), a hairline border, and a soft shadow. Used directly
/// by `GlassCard` (a standalone widget) and, as a `List`/`Form` row
/// background, by `View.glassRows()` below.
private struct GlassSurface: View {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.5), lineWidth: 1)
            )
    }
}

/// Wraps `content` in a standalone translucent card — `OverviewView`'s
/// dashboard grid is built entirely out of these, one per widget (Timer,
/// Deadlines, Transactions, Projects Progress, Net Worth, Work Hours).
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

    public init(minHeight: CGFloat = GlassCard.defaultMinHeight, @ViewBuilder content: () -> Content) {
        self.minHeight = minHeight
        self.content = content()
    }

    public var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
            .background(GlassSurface(cornerRadius: GlassStyle.cardCornerRadius))
            .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 8)
    }
}

extension View {
    /// Applies the app-wide glass backdrop behind a `NavigationStack`'s root
    /// `List`/`Form`, and hides that container's own opaque scroll
    /// background so the backdrop — and, per-row, `.ultraThinMaterial` from
    /// `glassRows()` — actually shows through. Every screen's root
    /// `List`/`Form`, and every `Form`-based create/edit sheet, calls this
    /// once on itself.
    public func glassScreenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
    }

    /// The row-level counterpart: a translucent white-glass row background
    /// and a hidden separator, so rows read as small glass cards floating
    /// on the backdrop `glassScreenBackground()` provides, instead of plain
    /// opaque rows. `.listRowBackground`/`.listRowSeparator` cascade from
    /// whatever they're attached to down to every row inside it, so this is
    /// meant to be called once per `Section` (or bare `ForEach`) — not once
    /// per individual row.
    public func glassRows() -> some View {
        self
            .listRowBackground(
                GlassSurface(cornerRadius: GlassStyle.rowCornerRadius)
                    .padding(.vertical, 2)
            )
            .listRowSeparator(.hidden)
    }
}
