import SwiftUI

/// Shared create/edit form: the same sheet serves "New Project" and "Edit
/// Project" — a name field and a Deadline toggle (mirrors `TaskFormSheet`).
/// Left in the shared chassis look rather than a bespoke glass re-theme — a
/// `Form`'s native controls don't read as "liquid glass" however they're
/// dressed, so there's nothing this screen's own device would add here
/// (mirrors `AccountFormSheet`'s identical reasoning).
struct ProjectFormSheet: View {
    let title: String
    let onSave: (ProjectFormValues) async -> Void

    @State private var name: String
    @State private var hasDeadline: Bool
    @State private var dueDate: Date
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialName: String, initialDueDate: Date?, onSave: @escaping (ProjectFormValues) async -> Void) {
        self.title = title
        self.onSave = onSave
        self._name = State(initialValue: initialName)
        self._hasDeadline = State(initialValue: initialDueDate != nil)
        self._dueDate = State(initialValue: initialDueDate ?? Date())
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    TextField("Name", text: $name)
                        .pccField()
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
                        let values = ProjectFormValues(name: trimmedName, dueDate: selectedDueDate)
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
