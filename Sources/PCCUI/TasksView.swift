import SwiftUI

/// Minimal Mac/iOS screen for ticket #4: lists Tasks (optionally scoped to
/// one Project via `TasksViewModel`'s `scopedProjectID`), and supports
/// creating, editing, deleting, completing/uncompleting, reassigning a
/// Task's Project, and setting/clearing its Deadline (ticket #5). One shared
/// SwiftUI view for both platforms — no platform-specific chrome, per the
/// ticket's "minimal" scope (mirrors `ProjectsView`).
public struct TasksView: View {
    @ObservedObject private var viewModel: TasksViewModel

    public init(viewModel: TasksViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TasksContent(viewModel: viewModel)
            .screenTheme(.fieldManual)
    }
}

/// The screen's actual content — split out from `TasksView` itself so
/// `.screenTheme(.fieldManual)` (applied in that struct's body, above) is
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
                    taskList
                }
            }
            // Applied once here, covering both branches, rather than on
            // `taskList` alone — `emptyState` had no themed background at
            // all before this (a pre-existing gap; `ProjectsView` had the
            // same one, fixed the same way).
            .background(PanelBackground())
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

    private var taskList: some View {
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.tasks) { task in
                    HStack(alignment: .top, spacing: 14) {
                        Button {
                            Task {
                                await viewModel.setCompletion(task, isComplete: !task.isComplete)
                            }
                        } label: {
                            TacticalCheckbox(isComplete: task.isComplete)
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #endif

                        Button {
                            editingTask = task
                        } label: {
                            VStack(alignment: .leading) {
                                Text(task.title)
                                    .strikethrough(task.isComplete)
                                if let notes = task.notes {
                                    Text(notes)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if let dueDate = task.dueDate {
                                    Text(dueDate, style: .date)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Self.isOverdue(task) ? theme.signalRed(colorScheme) : .secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #endif

                        // A sibling in the row's own HStack, not an
                        // overlay bled past the row's edge — an earlier
                        // pass did that to mimic a diagonal mockup effect
                        // and it repeatedly fought the row's real bounds
                        // across several rounds of screenshots; see
                        // OverdueStamp's own doc comment for why it's a
                        // plain unrotated tag now.
                        if Self.isOverdue(task) {
                            OverdueStamp()
                        }
                    }
                    // No horizontal padding: List already reserves its
                    // own leading/trailing inset per row, same as every
                    // other screen's rows — adding more on top of that
                    // doubled up and read as "too far from the edge"
                    // (caught via screenshot on a real Task).
                    .padding(.vertical, 10)
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { viewModel.tasks[$0] }
                    Task {
                        for task in toDelete {
                            await viewModel.deleteTask(task)
                        }
                    }
                }
                .panelRows()
            }
        }
        .scrollContentBackground(.hidden)
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
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var overallStatus: PanelStatus {
        overdueCount > 0 ? .critical : .nominal
    }

    private var overdueCount: Int {
        viewModel.tasks.filter(Self.isOverdue).count
    }

    private static func isOverdue(_ task: PCCTask) -> Bool {
        guard let dueDate = task.dueDate, !task.isComplete else { return false }
        return dueDate < Date()
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
            .panelScreenBackground()
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

// MARK: - Field Manual theme

extension ScreenTheme {
    /// `TasksView`'s own vibe: completing a Task is the one action this
    /// screen exists for, so the checkbox itself carries the theme rather
    /// than a decorative device elsewhere. Khaki paper instead of this
    /// app's usual blue/gray voids, a safety-orange accent, and signal
    /// green/red both shifted toward olive/rust rather than the default
    /// palette's brighter teal-green/pink-red — this screen's own
    /// complete/overdue colors, not the shared ones.
    fileprivate static let fieldManual = ScreenTheme(
        panelVoid: { $0 == .dark ? Color(hex: 0x1A1C14) : Color(hex: 0xEFEBDC) },
        panelSurface: { $0 == .dark ? Color(hex: 0x24261C) : Color(hex: 0xFAF8EF) },
        panelLine: { $0 == .dark ? Color(hex: 0x3F4230) : Color(hex: 0xD2CBAF) },
        accent: { $0 == .dark ? Color(hex: 0xFF8A3D) : Color(hex: 0xC24E14) },
        signalGreen: { $0 == .dark ? Color(hex: 0x8FBF5E) : Color(hex: 0x4C6B2A) },
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: { $0 == .dark ? Color(hex: 0xFF6B52) : Color(hex: 0xB23A22) }
    )
}

// MARK: - Tactical checkbox

/// This screen's signature device: a bold square marked with a hand-drawn
/// double stroke when complete, instead of the default circle/checkmark
/// SF Symbol — a field-manual form's checkbox is marked with a pen, not
/// softened into a rounded UI toggle.
private struct TacticalCheckbox: View {
    let isComplete: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(isComplete ? theme.signalGreen(colorScheme) : Color.secondary, lineWidth: 2)
            if isComplete {
                CheckmarkShape()
                    .stroke(theme.signalGreen(colorScheme), style: StrokeStyle(lineWidth: 2.4, lineCap: .square, lineJoin: .miter))
                    .padding(3)
            }
        }
        .frame(width: 20, height: 20)
        // A stroked/outlined shape only registers taps on its drawn
        // pixels by default — the empty interior of the square isn't
        // hit-testable on its own, unlike the filled SF Symbol icon this
        // replaced. Without this, the checkbox looked right but tapping
        // its center did nothing (caught directly: the user couldn't
        // click it at all).
        .contentShape(Rectangle())
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

/// A rectangular ink-block tag on an overdue Task's row — a field-manual
/// rubber stamp, not a soft rounded pill badge. Deliberately *not*
/// rotated: a diagonal version looked the part in the mockup, but a
/// rotated shape's rendered bounds don't match its layout frame, and
/// getting that to sit cleanly against a row's real edges (rather than
/// crowding them or clipping) turned into more fuss than the effect was
/// worth — caught over several rounds of real screenshots. Sharp corners
/// and a solid fill carry the "stamped," not the angle.
private struct OverdueStamp: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        Text("OVERDUE")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.2)
            // Fixed regardless of theme — this sits on a solid signalRed
            // badge, not the screen's own surface, so it doesn't need to
            // track Light/Dark the way ordinary text does.
            .foregroundStyle(Color(hex: 0xFBF5EC))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.signalRed(colorScheme))
    }
}
