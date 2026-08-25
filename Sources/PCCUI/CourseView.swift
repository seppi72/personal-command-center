import SwiftUI

/// Minimal Mac/iOS screen for ticket #19: lists Courses, and supports
/// creating, editing (name, Term, setting/clearing a Deadline), and deleting
/// one. One shared SwiftUI view for both platforms — no platform-specific
/// chrome, per the ticket's "minimal" scope (mirrors `ProjectsView`).
public struct CourseView: View {
    @ObservedObject private var viewModel: CoursesViewModel
    @State private var isPresentingNewCourseSheet = false
    @State private var editingCourse: Course?

    public init(viewModel: CoursesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.courses.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    courseList
                }
            }
            .navigationTitle("Courses")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewCourseSheet = true
                    } label: {
                        Label("Add Course", systemImage: "plus")
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
            .sheet(isPresented: $isPresentingNewCourseSheet) {
                CourseFormSheet(
                    title: "New Course",
                    initialName: "",
                    initialTermMonth: Calendar.current.component(.month, from: Date()),
                    initialTermYear: Calendar.current.component(.year, from: Date()),
                    initialDueDate: nil
                ) { values in
                    await viewModel.createCourse(values)
                }
            }
            .sheet(item: $editingCourse) { course in
                CourseFormSheet(
                    title: "Edit Course",
                    initialName: course.name,
                    initialTermMonth: course.termMonth,
                    initialTermYear: course.termYear,
                    initialDueDate: course.dueDate
                ) { values in
                    await viewModel.updateCourse(course, with: values)
                }
            }
        }
    }

    private var courseList: some View {
        List {
            ForEach(viewModel.courses) { course in
                Button {
                    editingCourse = course
                } label: {
                    VStack(alignment: .leading) {
                        Text(course.name)
                        Text(Self.termLabel(month: course.termMonth, year: course.termYear))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let dueDate = course.dueDate {
                            Text(dueDate, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            }
            .onDelete { offsets in
                let toDelete = offsets.map { viewModel.courses[$0] }
                Task {
                    for course in toDelete {
                        await viewModel.deleteCourse(course)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Courses")
                .font(.headline)
            Text("Tap + to create your first Course.")
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

    /// e.g. "September 2026" — the Term's owner-facing rendering, shared by
    /// the row caption here (`CourseFormSheet` renders the same two fields
    /// as editable controls instead).
    static func termLabel(month: Int, year: Int) -> String {
        let symbols = Calendar.current.monthSymbols
        guard (1...12).contains(month), symbols.indices.contains(month - 1) else {
            return "\(month)/\(year)"
        }
        return "\(symbols[month - 1]) \(year)"
    }
}

/// Shared create/edit form: the same sheet serves "New Course" and "Edit
/// Course" — a name field, Term (month/year) fields, and a Deadline toggle
/// (mirrors `ProjectFormSheet`).
struct CourseFormSheet: View {
    let title: String
    let onSave: (CourseFormValues) async -> Void

    @State private var name: String
    @State private var termMonth: Int
    @State private var termYear: Int
    @State private var hasDeadline: Bool
    @State private var dueDate: Date
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialName: String,
        initialTermMonth: Int,
        initialTermYear: Int,
        initialDueDate: Date?,
        onSave: @escaping (CourseFormValues) async -> Void
    ) {
        self.title = title
        self.onSave = onSave
        self._name = State(initialValue: initialName)
        self._termMonth = State(initialValue: initialTermMonth)
        self._termYear = State(initialValue: initialTermYear)
        self._hasDeadline = State(initialValue: initialDueDate != nil)
        self._dueDate = State(initialValue: initialDueDate ?? Date())
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `nil` unless the "Has deadline" toggle is on — SwiftUI's `DatePicker`
    /// has no built-in optional-date mode, so the toggle stands in for one
    /// (mirrors `ProjectFormSheet.selectedDueDate`).
    private var selectedDueDate: Date? {
        hasDeadline ? dueDate : nil
    }

    private static let monthSymbols = Calendar.current.monthSymbols

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Term") {
                    Picker("Month", selection: $termMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(Self.monthSymbols[month - 1]).tag(month)
                        }
                    }
                    Stepper("Year: \(termYear)", value: $termYear, in: 1900...3000)
                }
                Section("Deadline") {
                    Toggle("Has deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let values = CourseFormValues(
                            name: trimmedName,
                            termMonth: termMonth,
                            termYear: termYear,
                            dueDate: selectedDueDate
                        )
                        Task {
                            await onSave(values)
                            dismiss()
                        }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}
