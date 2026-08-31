import SwiftUI

/// Minimal Mac/iOS screen for ticket #6: lists Personal Commitments, and
/// supports creating, editing, and deleting one — each mutation pushes to
/// the external Calendar via CalDAV on the backend (`CalendarSyncService`),
/// surfaced here as a per-row sync-status badge. One shared SwiftUI view
/// for both platforms — no platform-specific chrome, per the ticket's
/// "minimal" scope (mirrors `ProjectsView`/`TasksView`).
public struct PersonalCommitmentsView: View {
    @ObservedObject private var viewModel: PersonalCommitmentsViewModel
    @State private var isPresentingNewCommitmentSheet = false
    @State private var editingCommitment: PersonalCommitment?

    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: PersonalCommitmentsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.commitments.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    commitmentList
                }
            }
            .navigationTitle("Personal Commitments")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewCommitmentSheet = true
                    } label: {
                        Label("Add Commitment", systemImage: "plus")
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
            .commitmentEditingSheets(
                isPresentingNewCommitmentSheet: $isPresentingNewCommitmentSheet,
                editingCommitment: $editingCommitment,
                courses: viewModel.courses,
                onCreate: { values in await viewModel.createCommitment(values) },
                onUpdate: { commitment, values in await viewModel.updateCommitment(commitment, with: values) }
            )
        }
    }

    private var commitmentList: some View {
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.commitments) { commitment in
                    Button {
                        editingCommitment = commitment
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(commitment.title)
                                Spacer()
                                SyncStatusBadge(syncStatus: commitment.syncStatus)
                            }
                            Text(commitment.startDate, style: .date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let recurrenceRule = commitment.recurrenceRule {
                                Text(recurrenceRule)
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
                    let toDelete = offsets.map { viewModel.commitments[$0] }
                    Task {
                        for commitment in toDelete {
                            await viewModel.deleteCommitment(commitment)
                        }
                    }
                }
                .glassRows()
            }
        }
        .glassScreenBackground()
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
                .fill(GlassStyle.panelLine(for: colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var failedSyncCount: Int {
        viewModel.commitments.filter { $0.syncStatus == .failed }.count
    }

    private var overallStatus: PanelStatus {
        failedSyncCount > 0 ? .critical : .nominal
    }

    private var statusStripText: String {
        let count = viewModel.commitments.count
        let noun = count == 1 ? "COMMITMENT" : "COMMITMENTS"
        let flagText = failedSyncCount > 0 ? "\(failedSyncCount) SYNC FAILED" : "ALL SYNCED"
        return "\(count) \(noun)   ·   \(flagText)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Personal Commitments")
                .font(.headline)
            Text("Tap + to schedule your first one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shared create/edit form: the same sheet serves "New Commitment" and
/// "Edit Commitment" — a title, start/end time, and an optional raw
/// recurrence rule (mirrors `TaskFormSheet`/`ProjectFormSheet`).
struct PersonalCommitmentFormSheet: View {
    let title: String
    let courses: [Course]
    let onSave: (PersonalCommitmentFormValues) async -> Void

    @State private var commitmentTitle: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var recurrenceRule: String
    @State private var courseID: UUID?
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialValues: PersonalCommitmentFormValues?,
        courses: [Course],
        onSave: @escaping (PersonalCommitmentFormValues) async -> Void
    ) {
        self.title = title
        self.courses = courses
        self.onSave = onSave
        let defaultStart = Date()
        self._commitmentTitle = State(initialValue: initialValues?.title ?? "")
        self._startDate = State(initialValue: initialValues?.startDate ?? defaultStart)
        self._endDate = State(initialValue: initialValues?.endDate ?? defaultStart.addingTimeInterval(3600))
        self._recurrenceRule = State(initialValue: initialValues?.recurrenceRule ?? "")
        self._courseID = State(initialValue: initialValues?.courseID)
    }

    private var trimmedTitle: String {
        commitmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRecurrenceRule: String? {
        let trimmed = recurrenceRule.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var isEndAfterStart: Bool {
        endDate > startDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $commitmentTitle)
                        .pccField()
                    DatePicker("Starts", selection: $startDate)
                    DatePicker("Ends", selection: $endDate)
                    if !isEndAfterStart {
                        Text("End time must be after start time.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField("Recurrence (e.g. FREQ=WEEKLY)", text: $recurrenceRule)
                        .pccField()
                    // Optional and standalone — unlike `TaskFormSheet`'s
                    // Project/Course pickers, there's no other container this
                    // one is mutually exclusive with (spec #56).
                    PCCMenuPicker(
                        "Course", selection: $courseID,
                        options: [(UUID?.none, "None")] + courses.map { (Optional($0.id), $0.name) }
                    )
                }
                .glassRows()
            }
            .glassScreenBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let values = PersonalCommitmentFormValues(
                            title: trimmedTitle,
                            startDate: startDate,
                            endDate: endDate,
                            recurrenceRule: trimmedRecurrenceRule,
                            courseID: courseID
                        )
                        Task {
                            await onSave(values)
                            dismiss()
                        }
                    }
                    .disabled(trimmedTitle.isEmpty || !isEndAfterStart)
                }
            }
        }
    }
}
