import SwiftUI

/// Reusable form controls that sit on top of `PCCChassis.swift`'s
/// surface tokens — this file is the "interactive control" half of the
/// design system (dropdowns, date ranges, text fields), where that one is
/// the "surface" half (cards, rows, backdrop). Introduced to replace every
/// screen's own default-styled `Picker`/raw `DatePicker` pair with one
/// consistent, compact, custom-drawn vocabulary instead of each form
/// re-deriving its own — every create/edit sheet and every filter/range
/// control in `PCCUI` is built from the pieces here.
///
/// Two different "the control sits on X" contexts each need a different
/// treatment, which is why there are two shapes below rather than one:
/// `PCCMenuPicker` (an already-boxed `List`/`Form` row picks up its box from
/// `.panelRows()`, so the control itself stays a plain inline label+value+
/// chevron) and `PCCControlChip`/`PCCDateRangeControl` (open card content
/// has no such box yet, so the control draws its own compact chip).

// MARK: - Shared control chip surface

/// The compact "chip" background `PCCDateRangeControl` and boxed
/// `PCCMenuPicker`s use — a small pill/rounded-rect distinct from a
/// standalone panel's bigger, softer card surface, sized and tinted to read
/// as a clickable control rather than a static panel. Built from `.primary`
/// opacity rather than `PanelSurface`'s explicit light/dark branching: a
/// semantic color already adapts (dark tint in light mode, light tint in
/// dark mode) without needing its own `colorScheme` check.
private struct PCCControlChipBackground: View {
    var isPressed: Bool = false
    var isHovering: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: PCCChassis.controlCornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: PCCChassis.controlCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PCCChassis.controlCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }

    private var fillOpacity: Double {
        if isPressed { return 0.14 }
        if isHovering { return 0.10 }
        return 0.055
    }
}

/// The `ButtonStyle` every card-context control chip (`PCCDateRangeControl`,
/// a `.boxed`-style `PCCMenuPicker`) uses — `PCCControlChipBackground` plus
/// compact padding and a pressed-state scale dip, with a macOS-only hover
/// highlight (`.onHover` has no iOS equivalent; touch has no hover state to
/// show).
public struct PCCControlChipStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PCCControlChipLabel(configuration: configuration)
    }

    private struct PCCControlChipLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(PCCControlChipBackground(isPressed: configuration.isPressed, isHovering: isHovering))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                #if os(macOS)
                .onHover { isHovering = $0 }
                #endif
        }
    }
}

extension ButtonStyle where Self == PCCControlChipStyle {
    public static var pccControlChip: PCCControlChipStyle { PCCControlChipStyle() }
}

// MARK: - Dropdown / menu picker

/// How a `PCCMenuPicker` renders its trigger: `.inline` for a row already
/// sitting inside a `.panelRows()`-styled `List`/`Form` Section (the row
/// itself is the box, so the control is just label + value + chevron), or
/// `.boxed` for one placed directly in open card content, which draws its
/// own `PCCControlChipStyle` chip the way `PCCDateRangeControl` does.
public enum PCCMenuPickerStyle {
    case inline
    case boxed
}

/// A compact dropdown: a label, the current value, and a chevron, opening a
/// native `Menu` with a checkmark on the selected option — replaces the
/// default `Picker` throughout this package, whose own system styling
/// (an oversized bordered pulldown on macOS, a disclosure-style row on iOS)
/// reads as generic/default rather than intentional next to this app's
/// custom glass surfaces. `Value: Hashable` covers both a plain enum
/// selection (e.g. Account `Type`) and an optional-id "attach to one of
/// these, or None" selection (`Value == UUID?`) with the same type — an
/// entry with `value: nil` in `options` is exactly what "None" already
/// means to a `UUID?`-keyed `Picker` elsewhere in this package.
public struct PCCMenuPicker<Value: Hashable>: View {
    private let label: String
    @Binding private var selection: Value
    private let options: [(value: Value, title: String)]
    private let style: PCCMenuPickerStyle
    private let placeholder: String

    public init(
        _ label: String,
        selection: Binding<Value>,
        options: [(value: Value, title: String)],
        style: PCCMenuPickerStyle = .inline,
        placeholder: String = "Select"
    ) {
        self.label = label
        self._selection = selection
        self.options = options
        self.style = style
        self.placeholder = placeholder
    }

    public var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            triggerLabel
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
    }

    /// The background is applied directly here (rather than via a
    /// `ButtonStyle`) so `.boxed` looks identical on both platforms — macOS
    /// and iOS don't route a `Menu`'s trigger through `ButtonStyle`
    /// consistently, but every platform renders whatever view this closure
    /// returns verbatim.
    private var triggerLabel: some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(currentTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .modifier(PCCMenuPickerChrome(style: style))
    }

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? placeholder
    }
}

/// `.boxed` wraps the trigger in a `PCCControlChipBackground` chip;
/// `.inline` leaves it bare (the row it sits in is already the box).
private struct PCCMenuPickerChrome: ViewModifier {
    let style: PCCMenuPickerStyle

    func body(content: Content) -> some View {
        switch style {
        case .inline:
            content
        case .boxed:
            content
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(PCCControlChipBackground())
        }
    }
}

// MARK: - Date range

/// A date-range filter's preset choices — `Today`/`This Week`/`Last 7
/// Days`/`This Month`/`Last Month` cover the common cases without opening a
/// calendar at all; `Custom` is the escape hatch for anything else.
public enum DateRangeOption: String, CaseIterable, Identifiable, Sendable {
    case today, thisWeek, last7Days, thisMonth, lastMonth, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .last7Days: return "Last 7 Days"
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        case .custom: return "Custom"
        }
    }
}

/// One control's worth of date-range state: which preset is active, plus
/// the two dates `.custom` reads. The single type every range-filtered
/// screen (`OverviewViewModel`'s Finances card, `FinancesReportingViewModel`,
/// `FinancesReportingViewModel`) now holds instead of each keeping its own bare
/// `start`/`end` pair — one place defines what "This Week" or "Last Month"
/// actually means, rather than each screen re-deriving (or subtly
/// disagreeing on) the same calendar math.
public struct DateRangeSelection: Sendable, Equatable {
    public var option: DateRangeOption
    public var customStart: Date
    public var customEnd: Date

    public init(option: DateRangeOption = .last7Days, customStart: Date? = nil, customEnd: Date? = nil) {
        self.option = option
        let today = Calendar.current.startOfDay(for: Date())
        self.customStart = customStart ?? (Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today)
        self.customEnd = customEnd ?? Date()
    }

    /// The concrete `[start, end]` this selection currently resolves to.
    /// Monday-anchored for `.thisWeek` regardless of the current locale's
    /// `firstWeekday` — the same explicit, locale-independent calculation
    /// the deleted `WorkHoursViewModel` used to compute its own "current week" default
    /// with (its own prior doc comment explained why: weekday `1` is Sunday
    /// through `7` Saturday, so days-since-Monday is `weekday - 2`, except
    /// Sunday, which needs `6` rather than the `-1` that formula would give
    /// it), now centralized here instead of duplicated per screen.
    public var resolvedRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        switch option {
        case .today:
            return (today, now)
        case .thisWeek:
            let weekday = calendar.component(.weekday, from: today)
            let daysSinceMonday = weekday == 1 ? 6 : weekday - 2
            let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
            return (monday, now)
        case .last7Days:
            return (calendar.date(byAdding: .day, value: -7, to: today) ?? today, now)
        case .thisMonth:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? today
            return (startOfMonth, now)
        case .lastMonth:
            let startOfThisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? today
            let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? startOfThisMonth
            let endOfLastMonth = calendar.date(byAdding: .second, value: -1, to: startOfThisMonth) ?? startOfThisMonth
            return (startOfLastMonth, endOfLastMonth)
        case .custom:
            return (customStart, customEnd)
        }
    }

    /// What `PCCDateRangeControl`'s trigger shows: the preset's own name
    /// for a preset ("This Month" is more scannable than the dates it
    /// covers), or the formatted date span for `.custom`.
    public var displayLabel: String {
        option == .custom ? Self.formattedRange(customStart, customEnd) : option.title
    }

    /// e.g. "Aug 24 – Aug 31, 2026" — both years shown only when they
    /// differ, matching how a person would actually say a cross-year range.
    public static func formattedRange(_ start: Date, _ end: Date) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        let startFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = startFormat
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "MMM d, yyyy"
        return "\(startFormatter.string(from: start)) – \(endFormatter.string(from: end))"
    }
}

/// A single compact chip that replaces a pair of raw side-by-side
/// `DatePicker`s: tapping it opens a popover listing `DateRangeOption`'s
/// presets (checkmark on the active one) plus, only when `Custom` is
/// selected, two `DatePicker`s for the exact start/end. `onChange` fires
/// after every selection that actually changes the resolved range — a
/// preset tap closes the popover and fires immediately; a custom date edit
/// fires on each edit, mirroring every other control-change-triggers-reload
/// convention already used throughout this package (e.g.
/// `FinancesReportingView`'s prior raw `DatePicker`s).
public struct PCCDateRangeControl: View {
    @Binding private var selection: DateRangeSelection
    private let onChange: () -> Void
    @State private var isPresented = false

    public init(selection: Binding<DateRangeSelection>, onChange: @escaping () -> Void) {
        self._selection = selection
        self.onChange = onChange
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                Text(selection.displayLabel)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .buttonStyle(.pccControlChip)
        .popover(isPresented: $isPresented) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DateRangeOption.allCases) { option in
                presetRow(option)
            }
            if selection.option == .custom {
                Divider()
                    .padding(.vertical, 6)
                customRangeFields
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private func presetRow(_ option: DateRangeOption) -> some View {
        Button {
            selection.option = option
            if option != .custom {
                isPresented = false
                onChange()
            }
        } label: {
            HStack {
                Text(option.title)
                Spacer()
                if selection.option == option {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }

    private var customRangeFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Start", selection: $selection.customStart, in: ...selection.customEnd, displayedComponents: .date)
                .onChange(of: selection.customStart) { _ in onChange() }
            DatePicker("End", selection: $selection.customEnd, in: selection.customStart..., displayedComponents: .date)
                .onChange(of: selection.customEnd) { _ in onChange() }
            Button("Done") { isPresented = false }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Text fields

extension View {
    /// The text field treatment every `TextField`/`SecureField` in this
    /// package uses inside a `.panelRows()` Section — `.plain` strips the
    /// platform's own bordered/boxed field chrome (macOS's native
    /// `NSTextField` box in particular reads oddly floating on top of an
    /// already-custom glass row background) so typed text sits directly on
    /// the row, the same way a label or any other row content already
    /// does — consistent typography is the only other thing this adds.
    public func pccField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.body)
    }
}
