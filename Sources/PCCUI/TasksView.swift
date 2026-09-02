import SwiftUI

/// Minimal Mac/iOS screen for ticket #4: lists Tasks (optionally scoped to
/// one Project via `TasksViewModel`'s `scopedProjectID`), and supports
/// creating, editing, deleting, completing/uncompleting, reassigning a
/// Task's Project, and setting/clearing its Deadline (ticket #5). One shared
/// SwiftUI view for both platforms — no platform-specific chrome, per the
/// ticket's "minimal" scope (mirrors `ProjectsView`).
///
/// On the shared Liquid Glass system since issue #68 — full-width
/// `GlassBubble` rows on `GlassScreenBackground()`, replacing the earlier
/// field-manual costume (khaki paper, a hand-inked checkbox, an ink-stamp
/// "OVERDUE" tag) `git log` on this file still shows. The checkbox and the
/// overdue flag both survive as devices, just redrawn in glass — see
/// `GlassCheckbox`/`OverdueBadge` below.
public struct TasksView: View {
    @ObservedObject private var viewModel: TasksViewModel

    public init(viewModel: TasksViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TasksContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `TasksView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct TasksContent: View {
    @ObservedObject var viewModel: TasksViewModel
    @State private var isPresentingNewTaskSheet = false
    @State private var editingTask: PCCTask?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.tasks.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    taskScroll
                }
            }
            // Applied once here, covering both branches, rather than on
            // `taskScroll` alone — `emptyState` had no themed background at
            // all before this (a pre-existing gap; `ProjectsView` had the
            // same one, fixed the same way).
            .background(GlassScreenBackground())
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewTaskSheet = true
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Error", isPresented: isShowingError, presenting: viewModel.errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: $isPresentingNewTaskSheet) {
                TaskFormSheet(
                    title: "New Task",
                    initialTitle: "",
                    initialNotes: "",
                    initialProjectID: nil,
                    initialCourseID: nil,
                    initialDueDate: nil,
                    projects: viewModel.projects,
                    courses: viewModel.courses
                ) { values in
                    await viewModel.createTask(values)
                }
            }
            .sheet(item: $editingTask) { task in
                TaskFormSheet(
                    title: "Edit Task",
                    initialTitle: task.title,
                    initialNotes: task.notes ?? "",
                    initialProjectID: task.projectID,
                    initialCourseID: task.courseID,
                    initialDueDate: task.dueDate,
                    projects: viewModel.projects,
                    courses: viewModel.courses
                ) { values in
                    await viewModel.updateTask(task, with: values)
                }
            }
        }
    }

    /// A `ScrollView` of `TaskBubble`s rather than a `List` — this screen's
    /// whole point is liquid glass floating on plain white/black, which
    /// needs each row to draw its own translucent Material-backed shape
    /// (the shared `GlassBubble`) rather than a native list container's
    /// opaque row fill (mirrors `AccountsView`'s own move from `List` to
    /// `ScrollView` + custom cards for the same reason).
    private var taskScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip
                VStack(spacing: 14) {
                    ForEach(viewModel.tasks) { task in
                        TaskBubble(
                            task: task,
                            isOverdue: TasksViewModel.isOverdue(task),
                            onToggleComplete: {
                                Task { await viewModel.setCompletion(task, isComplete: !task.isComplete) }
                            },
                            onTap: { editingTask = task },
                            onDelete: { Task { await viewModel.deleteTask(task) } }
                        )
                    }
                }
                .padding(.top, 18)
            }
            .padding(PCCChassis.outerMargin)
        }
    }

    // MARK: - Status strip

    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(overallStatus)
            Text(statusStripText)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.bottom, 12)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var overallStatus: PanelStatus {
        overdueCount > 0 ? .critical : .nominal
    }

    private var overdueCount: Int {
        viewModel.tasks.filter { TasksViewModel.isOverdue($0) }.count
    }

    private var statusStripText: String {
        let count = viewModel.tasks.count
        let noun = count == 1 ? "TASK" : "TASKS"
        let flagText = overdueCount > 0 ? "\(overdueCount) OVERDUE" : "ALL CLEAR"
        return "\(count) \(noun)   ·   \(flagText)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Tasks")
                .font(.headline)
            Text("Tap + to create your first Task.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isShowing in if !isShowing { viewModel.errorMessage = nil } }
        )
    }
}

/// Shared create/edit form: the same sheet serves "New Task" and "Edit
/// Task" — a title, optional notes, a Project *or* Course picker (never
/// both — ADR-0003), and a Deadline toggle (mirrors `ProjectFormSheet`).
/// Its Section stays in the shared chassis look — a `Form`'s native
/// controls don't read as glass however they're dressed
/// (`AccountFormSheet`'s doc comment carries this reasoning in full) — but
/// its ground now repaints to `GlassScreenBackground()` via
/// `glassScreenBackground()`, per issue #68.
struct TaskFormSheet: View {
    let title: String
    let projects: [Project]
    let courses: [Course]
    let onSave: (TaskFormValues) async -> Void

    @State private var taskTitle: String
    @State private var notes: String
    @State private var projectID: UUID?
    @State private var courseID: UUID?
    @State private var hasDeadline: Bool
    @State private var dueDate: Date
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialTitle: String,
        initialNotes: String,
        initialProjectID: UUID?,
        initialCourseID: UUID?,
        initialDueDate: Date?,
        projects: [Project],
        courses: [Course],
        onSave: @escaping (TaskFormValues) async -> Void
    ) {
        self.title = title
        self.projects = projects
        self.courses = courses
        self.onSave = onSave
        self._taskTitle = State(initialValue: initialTitle)
        self._notes = State(initialValue: initialNotes)
        self._projectID = State(initialValue: initialProjectID)
        self._courseID = State(initialValue: initialCourseID)
        self._hasDeadline = State(initialValue: initialDueDate != nil)
        self._dueDate = State(initialValue: initialDueDate ?? Date())
    }

    private var trimmedTitle: String {
        taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `nil` unless the "Has deadline" toggle is on — SwiftUI's `DatePicker`
    /// has no built-in optional-date mode, so the toggle stands in for one.
    private var selectedDueDate: Date? {
        hasDeadline ? dueDate : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $taskTitle)
                        .pccField()
                    TextField("Notes", text: $notes)
                        .pccField()
                    // A Task belongs to at most one of {Project, Course}
                    // (ADR-0003) — picking one clears the other rather than
                    // leaving both pickers free to disagree.
                    PCCMenuPicker(
                        "Project", selection: $projectID,
                        options: [(UUID?.none, "None")] + projects.map { (Optional($0.id), $0.name) }
                    )
                    .onChange(of: projectID) { newValue in
                        if newValue != nil { courseID = nil }
                    }
                    PCCMenuPicker(
                        "Course", selection: $courseID,
                        options: [(UUID?.none, "None")] + courses.map { (Optional($0.id), $0.name) }
                    )
                    .onChange(of: courseID) { newValue in
                        if newValue != nil { projectID = nil }
                    }
                }
                .panelRows()
                Section("Deadline") {
                    Toggle("Has deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }
                .panelRows()
            }
            .glassScreenBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let values = TaskFormValues(
                            title: trimmedTitle,
                            notes: trimmedNotes,
                            projectID: projectID,
                            courseID: courseID,
                            dueDate: selectedDueDate
                        )
                        Task {
                            await onSave(values)
                            dismiss()
                        }
                    }
                    .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }
}

// MARK: - Task bubble

/// One Task row: the shared `GlassBubble` surface (`.fullWidth` size) with
/// this screen's own content on it — a `GlassCheckbox`, the title/notes/due
/// date, and an `OverdueBadge` when it's overdue. Set tighter than
/// `AccountBubble`/`TransactionBubble` (14pt vertical padding, not 20) so a
/// long Task list stays scannable rather than each row eating as much
/// vertical space as those screens' single hero-figure rows. The bubble's
/// material, tint, specular highlight and rim come from `PCCChassis`, not
/// from here; only the layout is this screen's.
private struct TaskBubble: View {
    let task: PCCTask
    let isOverdue: Bool
    let onToggleComplete: () -> Void
    let onTap: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let style: GlassBubbleStyle = .fullWidth

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: onToggleComplete) {
                GlassCheckbox(isComplete: task.isComplete)
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif

            Button(action: onTap) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.system(size: 15, weight: .semibold))
                            .strikethrough(task.isComplete)
                        if let notes = task.notes {
                            Text(notes)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let dueDate = task.dueDate {
                            Text(dueDate, style: .date)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(isOverdue ? theme.signalRed(colorScheme) : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if isOverdue {
                        OverdueBadge()
                    }
                }
                // Without this, only the rendered text/badge actually
                // registers a tap — the `.frame(maxWidth: .infinity)`
                // leading VStack above adds layout width but no
                // hit-testable area on its own, the same gap
                // `GlassCheckbox`'s own doc comment calls out for its
                // circle. Matches `AccountBubble`/`TransactionBubble`,
                // which give their own single-`Button` row the same fix.
                .contentShape(Rectangle())
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassBubble(Self.style)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Glass checkbox

/// This screen's completion device, redrawn in the glass language (issue
/// #68) — a small round glass well, cut from the same glass as the bubble
/// it sits inside (mirrors `AccountBubble`'s round type-icon well), holding
/// a checkmark tinted `signalGreen` once complete. Replaces the prior
/// `TacticalCheckbox`'s hand-inked square, which read as a field-manual
/// prop rather than something drawn out of this chassis's shared glass
/// vocabulary.
private struct GlassCheckbox: View {
    let isComplete: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(GlassBubble.tint(for: colorScheme)))
            .overlay(
                Circle().strokeBorder(
                    isComplete ? theme.signalGreen(colorScheme) : GlassBubble.rimColor(theme, colorScheme),
                    lineWidth: isComplete ? 1.5 : GlassBubble.rimWidth
                )
            )
            .frame(width: 24, height: 24)
            .overlay(
                Group {
                    if isComplete {
                        CheckmarkShape()
                            .stroke(theme.signalGreen(colorScheme), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .padding(6)
                    }
                }
            )
            // A mostly-transparent glass well only registers taps on its
            // drawn rim by default — without this, the empty interior isn't
            // hit-testable, the same gap `TacticalCheckbox`'s own doc
            // comment called out for the shape it replaces.
            .contentShape(Circle())
    }
}

/// A single continuous three-point checkmark stroke, scaled to whatever
/// rect it's drawn in — a proper `Shape.path(in:)` rather than a `Path`
/// literal built from fixed coordinates (the latter is what silently
/// dropped a stroke in `OverviewView`'s `HUDCorners` the first time
/// around; see that type's own doc comment).
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.82))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.20))
        return path
    }
}

/// An overdue Task's flag, redrawn in the glass language (issue #68) — a
/// small glass capsule chip tinted `signalRed`, cut from the same glass as
/// the bubble it sits inside, rather than the prior `OverdueStamp`'s
/// solid ink-block rubber-stamp fill. Text stays uppercase/tracked/
/// monospaced — that much of the original device survives — but the fill
/// is translucent Material, not solid signalRed.
private struct OverdueBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        Text("OVERDUE")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(theme.signalRed(colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(theme.signalRed(colorScheme).opacity(colorScheme == .dark ? 0.28 : 0.14)))
                    .overlay(Capsule().strokeBorder(theme.signalRed(colorScheme).opacity(0.6), lineWidth: 1))
            )
    }
}
