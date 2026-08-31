import SwiftUI

/// Minimal Mac/iOS live-timer control for ticket #28: shows the currently
/// running timer (what it's attached to, and since when) with Stop/Cancel
/// controls, or — when none is running — a container-kind picker and a
/// Start button. One shared view for both platforms, no platform-specific
/// chrome, per this repo's "minimal" scope (mirrors `TimeEntriesView`).
///
/// Laid out as one big hero card — segmented Task/Project/Client/Course
/// tabs, giant monospaced elapsed time, a large Start/Stop button — with a
/// second card below it listing that kind's items to attach to, rather than
/// the four stacked `Picker`s a plain `Form` would use: a large, focused
/// timer screen (glassmorphism dashboard pass) instead of one more settings
/// form. `TimeEntryContainer`'s "exactly one of four" rule (ADR-0004) falls
/// out of this shape for free — only one kind's item list is ever shown, so
/// only one id can ever be selected at a time, rather than needing the
/// four-Picker "picking one clears the other three" dance
/// `TimeEntryFormSheet` still uses.
public struct TimerView: View {
    @ObservedObject private var viewModel: TimerViewModel
    @State private var selectedKind: ContainerKind = .task
    @State private var selectedItemID: UUID?

    public init(viewModel: TimerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let activeTimer = viewModel.activeTimer {
                        runningCard(for: activeTimer)
                    } else {
                        idleCard
                        itemPickerCard
                    }
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .glassScreenBackground()
            .navigationTitle("Timer")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    // MARK: - Running

    private func runningCard(for entry: TimeEntry) -> some View {
        GlassCard(minHeight: 360) {
            VStack(spacing: 20) {
                Text(containerLabel(for: entry))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: entry.startDate, by: 1)) { context in
                    Text(Self.formattedElapsed(context.date.timeIntervalSince(entry.startDate)))
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Text("Started \(entry.startDate, style: .relative) ago")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                bigButton("Stop") {
                    Task { await viewModel.stop() }
                }
                Button("Cancel Timer", role: .destructive) {
                    Task { await viewModel.cancel() }
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Idle

    private var idleCard: some View {
        GlassCard(minHeight: 360) {
            VStack(spacing: 20) {
                kindTabs
                Text(Self.formattedElapsed(0))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary.opacity(0.4))
                Text(selectedItemID == nil ? "Choose a \(selectedKind.title) below to start" : "Ready to start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                bigButton("Start") {
                    guard let container else { return }
                    Task { await viewModel.start(container: container) }
                }
                .disabled(container == nil)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The segmented Task/Project/Client/Course tab row — the reference
    /// layout's mode tabs, repurposed here to pick which of `TimeEntry`'s
    /// four possible containers this Timer attaches to (ADR-0004) instead
    /// of a session type. Switching tabs clears `selectedItemID`: an id
    /// from the old kind's list wouldn't mean anything against the new
    /// kind's items.
    private var kindTabs: some View {
        HStack(spacing: 4) {
            ForEach(ContainerKind.allCases) { kind in
                Button {
                    guard kind != selectedKind else { return }
                    selectedKind = kind
                    selectedItemID = nil
                } label: {
                    Text(kind.title)
                        .font(.subheadline.weight(kind == selectedKind ? .bold : .regular))
                        .foregroundStyle(kind == selectedKind ? Color.primary : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(kind == selectedKind ? Color.primary.opacity(0.12) : Color.clear)
                        )
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            }
        }
    }

    private var itemPickerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose a \(selectedKind.title)")
                    .font(.headline)
                if currentItems.isEmpty {
                    Text("No \(selectedKind.title)s yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(currentItems, id: \.id) { item in
                            itemRow(item)
                        }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: (id: UUID, title: String)) -> some View {
        Button {
            selectedItemID = item.id
        } label: {
            HStack {
                Text(item.title)
                Spacer()
                if selectedItemID == item.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selectedItemID == item.id ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    /// A large pill-shaped call-to-action button — Start/Stop, spanning
    /// most of the hero card's width, matching the reference layout's own
    /// oversized button rather than a standard-size `Form` button.
    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Helpers

    private var container: TimeEntryContainer? {
        guard let selectedItemID else { return nil }
        switch selectedKind {
        case .task: return .task(selectedItemID)
        case .project: return .project(selectedItemID)
        case .client: return .client(selectedItemID)
        case .course: return .course(selectedItemID)
        }
    }

    private var currentItems: [(id: UUID, title: String)] {
        switch selectedKind {
        case .task: return viewModel.tasks.map { ($0.id, $0.title) }
        case .project: return viewModel.projects.map { ($0.id, $0.name) }
        case .client: return viewModel.clients.map { ($0.id, $0.name) }
        case .course: return viewModel.courses.map { ($0.id, $0.name) }
        }
    }

    /// The name of whichever Task/Project/Client/Course `entry` is attached
    /// to, looked up from the view model's already-loaded picker data —
    /// falls back to a placeholder rather than crashing if the referenced
    /// item isn't in the loaded lists. Mirrors `TimeEntriesView`'s own copy.
    private func containerLabel(for entry: TimeEntry) -> String {
        if let taskID = entry.taskID {
            return viewModel.tasks.first { $0.id == taskID }?.title ?? "Unknown Task"
        }
        if let projectID = entry.projectID {
            return viewModel.projects.first { $0.id == projectID }?.name ?? "Unknown Project"
        }
        if let clientID = entry.clientID {
            return viewModel.clients.first { $0.id == clientID }?.name ?? "Unknown Client"
        }
        if let courseID = entry.courseID {
            return viewModel.courses.first { $0.id == courseID }?.name ?? "Unknown Course"
        }
        return "Unattached"
    }

    /// "H:MM:SS" once past an hour, "MM:SS" until then — a Timer runs
    /// open-ended (no set session length, unlike a Pomodoro countdown), so
    /// this counts up rather than down. Also used, at `0`, to render the
    /// idle card's dimmed placeholder digits.
    private static func formattedElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

/// The four kinds of container a Time Entry can attach to (ADR-0004) — as a
/// `CaseIterable` enum so `TimerView`'s tab row can enumerate them, rather
/// than four separately-tracked optional ids each needing its own
/// "clear the other three" logic (`TimeEntryFormSheet`'s own shape).
/// Package-internal (not `private`) rather than scoped to this file — the
/// Overview dashboard's mini Timer (`OverviewView.swift`) reuses this same
/// enum for its own compact container-kind tabs.
enum ContainerKind: CaseIterable, Identifiable {
    case task, project, client, course

    var id: Self { self }

    var title: String {
        switch self {
        case .task: return "Task"
        case .project: return "Project"
        case .client: return "Client"
        case .course: return "Course"
        }
    }
}
