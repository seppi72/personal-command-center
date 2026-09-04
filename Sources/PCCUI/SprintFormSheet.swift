import SwiftUI

/// Shared create/edit form: the same sheet serves "New Sprint" and "Edit
/// Sprint" — a name field and start/end `DatePicker`s (mirrors
/// `ProjectFormSheet`). A Sprint's Project isn't editable here — it's set at
/// creation and never reassigned (`CONTEXT.md`).
struct SprintFormSheet: View {
    let title: String
    let onSave: (SprintFormValues) async -> Void

    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialName: String,
        initialStartDate: Date,
        initialEndDate: Date,
        onSave: @escaping (SprintFormValues) async -> Void
    ) {
        self.title = title
        self.onSave = onSave
        self._name = State(initialValue: initialName)
        self._startDate = State(initialValue: initialStartDate)
        self._endDate = State(initialValue: initialEndDate)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && endDate >= startDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .pccField()
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
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
                        let values = SprintFormValues(name: trimmedName, startDate: startDate, endDate: endDate)
                        Task {
                            await onSave(values)
                            dismiss()
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
