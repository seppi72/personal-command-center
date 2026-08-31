import SwiftUI

/// Minimal Mac/iOS screen for ticket #6: lists Personal Commitments, and
/// supports creating, editing, and deleting one — each mutation pushes to
/// the external Calendar via CalDAV on the backend (`CalendarSyncService`),
/// surfaced here as a per-row sync-status badge. One shared SwiftUI view
/// for both platforms — no platform-specific chrome, per the ticket's
/// "minimal" scope (mirrors `ProjectsView`/`TasksView`).
public struct PersonalCommitmentsView: View {
    @ObservedObject private var viewModel: PersonalCommitmentsViewModel

    public init(viewModel: PersonalCommitmentsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        PersonalCommitmentsContent(viewModel: viewModel)
            .screenTheme(.notebookPage)
    }
}

/// The screen's actual content — split out from `PersonalCommitmentsView`
/// itself so `.screenTheme(.notebookPage)` (applied in that struct's
/// body, above) is genuinely in effect by the time this struct's own
/// `body` reads `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s
/// doc comment in `PCCChassis.swift` for why the split is required.
private struct PersonalCommitmentsContent: View {
    @ObservedObject var viewModel: PersonalCommitmentsViewModel
    @State private var isPresentingNewCommitmentSheet = false
    @State private var editingCommitment: PersonalCommitment?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.commitments.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    commitmentList
                }
            }
            .background(PanelBackground())
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
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                // The one typographic break from every
                                // other screen's sans/mono language —
                                // this screen's whole signature, carrying
                                // "more human, less instrument-panel" on
                                // its own.
                                Text(commitment.title)
                                    .font(.system(size: 17, design: .serif))
                                Spacer()
                                SyncStatusBadge(syncStatus: commitment.syncStatus)
                            }
                            Text(commitment.startDate, style: .date)
                                .font(.system(size: 13, design: .serif).italic())
                                .foregroundStyle(.secondary)
                            if let recurrenceRule = commitment.recurrenceRule {
                                Text(recurrenceRule)
                                    .font(.caption)
                                    .foregroundStyle(theme.accent(colorScheme))
                            }
                        }
                        .padding(.vertical, 6)
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
                .notebookRows()
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Status strip

    /// A plain italic sentence rather than every other screen's uppercase
    /// tracked label — quieter, and read as something a person would
    /// actually say, matching this screen's own brief.
    private var statusStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StatusDot(overallStatus)
            Text(statusStripText)
                .font(.system(size: 15, design: .serif).italic())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
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

    private var failedSyncCount: Int {
        viewModel.commitments.filter { $0.syncStatus == .failed }.count
    }

    private var overallStatus: PanelStatus {
        failedSyncCount > 0 ? .critical : .nominal
    }

    private var statusStripText: String {
        let count = viewModel.commitments.count
        let noun = count == 1 ? "commitment" : "commitments"
        if failedSyncCount > 0 {
            let failedNoun = failedSyncCount == 1 ? "one didn't sync" : "\(failedSyncCount) didn't sync"
            return "\(count) \(noun) on your calendar — \(failedNoun)."
        }
        return "\(count) \(noun) on your calendar, all synced."
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Personal Commitments")
                .font(.system(size: 18, weight: .medium, design: .serif))
            Text("Tap + to schedule your first one.")
                .font(.system(size: 14, design: .serif).italic())
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

// MARK: - Notebook Page theme

extension ScreenTheme {
    /// `PersonalCommitmentsView`'s own vibe: a deliberate contrast from
    /// the rest of the app, not another loud console device — warm paper
    /// tones and a dusty-rose accent, quieter than the shared cyan/gold/
    /// blue/orange/red/yellow already in use elsewhere. Not the cream +
    /// terracotta combination that reads as a generic AI default — the
    /// rose here is cooler and dustier than terracotta, and paired with
    /// this screen's own serif typography rather than a high-contrast
    /// serif display treatment. Signal colors are left as
    /// `ScreenTheme.default`'s.
    fileprivate static let notebookPage = ScreenTheme(
        panelVoid: { $0 == .dark ? Color(hex: 0x221C16) : Color(hex: 0xF6EEE0) },
        panelSurface: { $0 == .dark ? Color(hex: 0x2C241C) : Color(hex: 0xFFFBF3) },
        panelLine: { $0 == .dark ? Color(hex: 0x4A3C2C) : Color(hex: 0xE8DCC8) },
        accent: { $0 == .dark ? Color(hex: 0xE4A0B0) : Color(hex: 0xA85A6E) },
        signalGreen: ScreenTheme.default.signalGreen,
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: ScreenTheme.default.signalRed
    )
}

// MARK: - Notebook rows

extension View {
    /// The row-level background for this screen alone — a softer, larger
    /// corner radius than the shared chassis's `panelRows()`, since this
    /// screen's whole point is reading as *less* instrument-panel than
    /// the rest of the app. A local equivalent of `panelRows()` rather
    /// than a chassis-wide radius override, since only this screen wants
    /// it — the rounder corners are this screen's own choice, not a
    /// device other screens should default to.
    fileprivate func notebookRows() -> some View {
        modifier(NotebookRowsModifier())
    }
}

private struct NotebookRowsModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    func body(content: Content) -> some View {
        content
            .listRowBackground(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.panelSurface(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(theme.panelLine(colorScheme), lineWidth: 1)
                    )
                    .padding(.vertical, 3)
            )
            .listRowSeparator(.hidden)
    }
}
