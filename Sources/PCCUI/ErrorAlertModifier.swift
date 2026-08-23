import SwiftUI

/// The "Error" alert `PersonalCommitmentsView`, `CalendarView`, and every
/// other screen in this package attach to surface their view model's
/// `errorMessage` — factored out so each screen shares one alert behavior
/// instead of its own copy of the same `Binding`/`.alert` boilerplate.
private struct ErrorAlertModifier: ViewModifier {
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        content.alert("Error", isPresented: isShowingError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isShowing in if !isShowing { errorMessage = nil } }
        )
    }
}

extension View {
    /// Attaches the shared error alert, bound to a view model's optional
    /// error-message property (e.g. `PersonalCommitmentsViewModel.errorMessage`,
    /// `CalendarViewModel.errorMessage`).
    func errorAlert(_ errorMessage: Binding<String?>) -> some View {
        modifier(ErrorAlertModifier(errorMessage: errorMessage))
    }
}
