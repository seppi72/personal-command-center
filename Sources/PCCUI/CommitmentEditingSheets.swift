import SwiftUI

/// The "New Commitment" / "Edit Commitment" sheet pair both
/// `PersonalCommitmentsView` and `CalendarView` attach — factored out so
/// the two screens share one create/edit flow, wired to the same
/// `PersonalCommitmentFormSheet`, instead of two independently-maintained
/// copies of the same `.sheet` pair.
private struct CommitmentEditingSheetsModifier: ViewModifier {
    @Binding var isPresentingNewCommitmentSheet: Bool
    @Binding var editingCommitment: PersonalCommitment?
    let onCreate: (PersonalCommitmentFormValues) async -> Void
    let onUpdate: (PersonalCommitment, PersonalCommitmentFormValues) async -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresentingNewCommitmentSheet) {
                PersonalCommitmentFormSheet(title: "New Commitment", initialValues: nil) { values in
                    await onCreate(values)
                }
            }
            .sheet(item: $editingCommitment) { commitment in
                PersonalCommitmentFormSheet(
                    title: "Edit Commitment",
                    initialValues: PersonalCommitmentFormValues(
                        title: commitment.title,
                        startDate: commitment.startDate,
                        endDate: commitment.endDate,
                        recurrenceRule: commitment.recurrenceRule
                    )
                ) { values in
                    await onUpdate(commitment, values)
                }
            }
    }
}

extension View {
    /// Attaches the shared "New Commitment" / "Edit Commitment" sheet pair.
    /// `isPresentingNewCommitmentSheet`/`editingCommitment` are the calling
    /// screen's own `@State`; `onCreate`/`onUpdate` forward to whichever
    /// view model owns that screen's Commitments
    /// (`PersonalCommitmentsViewModel` or `CalendarViewModel`).
    func commitmentEditingSheets(
        isPresentingNewCommitmentSheet: Binding<Bool>,
        editingCommitment: Binding<PersonalCommitment?>,
        onCreate: @escaping (PersonalCommitmentFormValues) async -> Void,
        onUpdate: @escaping (PersonalCommitment, PersonalCommitmentFormValues) async -> Void
    ) -> some View {
        modifier(
            CommitmentEditingSheetsModifier(
                isPresentingNewCommitmentSheet: isPresentingNewCommitmentSheet,
                editingCommitment: editingCommitment,
                onCreate: onCreate,
                onUpdate: onUpdate
            )
        )
    }
}
