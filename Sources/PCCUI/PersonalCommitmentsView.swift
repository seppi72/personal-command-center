import SwiftUI

/// Minimal Mac/iOS screen for ticket #6: lists Personal Commitments, and
/// supports creating, editing, and deleting one — each mutation pushes to
/// the external Calendar via CalDAV on the backend (`CalendarSyncService`),
/// surfaced here as a per-row sync-status badge. One shared SwiftUI view
/// for both platforms — no platform-specific chrome, per the ticket's
/// "minimal" scope (mirrors `WorkView`).
///
/// On the shared Liquid Glass system since issue #71 — full-width
/// `GlassBubble` rows on `GlassScreenBackground()`, replacing the earlier
/// notebook-page costume (warm paper tones, a dusty-rose accent, and a
/// serif "handwritten" title face) `git log` on this file still shows. The
/// notebook rules are deleted outright rather than redrawn in glass; these
/// rows are plain glass now, same as every other screen's.
public struct PersonalCommitmentsView: View {
    @ObservedObject private var viewModel: PersonalCommitmentsViewModel

    public init(viewModel: PersonalCommitmentsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        PersonalCommitmentsContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `PersonalCommitmentsView`
/// itself so `.screenTheme(.liquidGlass)` (applied in that struct's body,
/// above) is genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
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
                    commitmentScroll
                }
            }
            .background(GlassScreenBackground())
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

    /// A `ScrollView` of `CommitmentBubble`s rather than a `List` — this
    /// screen's whole point is liquid glass floating on plain white/black,
    /// which needs each row to draw its own translucent Material-backed
    /// shape (the shared `GlassBubble`) rather than a native list
    /// container's opaque row fill (mirrors `DeadlinesView`'s own move from
    /// `List` to `ScrollView` + custom bubbles for the same reason).
    /// Deletion moves from the old `List`'s swipe gesture onto each row's
    /// own context menu — a `ScrollView` has no `List`-style swipe gesture
    /// to give it for free (mirrors `CategoriesView`'s identical tradeoff).
    private var commitmentScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip
                VStack(spacing: 14) {
                    ForEach(viewModel.commitments) { commitment in
                        CommitmentBubble(commitment: commitment, onTap: { editingCommitment = commitment })
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteCommitment(commitment) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
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
/// recurrence rule (mirrors `TaskFormSheet`/`ProjectFormSheet`). Its
/// Section stays in the shared chassis look — a `Form`'s native controls
/// don't read as glass however they're dressed (`AccountFormSheet`'s doc
/// comment carries this reasoning in full) — but its ground now repaints to
/// `GlassScreenBackground()` via `glassScreenBackground()`, per issue #71.
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

// MARK: - Commitment bubble

/// One Commitment row: the shared `GlassBubble` surface (`.fullWidth` size)
/// with this screen's own content on it — title, start date, an optional
/// recurrence line, and a `SyncStatusBadge` — plain glass rows now that the
/// old notebook-page costume is gone (issue #71). The bubble's material,
/// tint, specular highlight and rim come from `PCCChassis`, not from here;
/// only the layout is this screen's.
private struct CommitmentBubble: View {
    let commitment: PersonalCommitment
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let style: GlassBubbleStyle = .fullWidth

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(commitment.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(commitment.startDate, style: .date)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let recurrenceRule = commitment.recurrenceRule {
                        Text(recurrenceRule)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SyncStatusBadge(syncStatus: commitment.syncStatus)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .glassBubble(Self.style)
    }
}
