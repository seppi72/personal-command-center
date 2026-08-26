import SwiftUI

/// Minimal Mac/iOS live-timer control for ticket #28: shows the currently
/// running timer (what it's attached to, and since when) with Stop/Cancel
/// controls, or — when none is running — a container picker and a Start
/// button. One shared view for both platforms, no platform-specific chrome,
/// per this repo's "minimal" scope (mirrors `TimeEntriesView`).
public struct TimerView: View {
    @ObservedObject private var viewModel: TimerViewModel
    @State private var taskID: UUID?
    @State private var projectID: UUID?
    @State private var clientID: UUID?
    @State private var courseID: UUID?

    public init(viewModel: TimerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let activeTimer = viewModel.activeTimer {
                    runningSection(for: activeTimer)
                } else {
                    startSection
                }
            }
            .navigationTitle("Timer")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .errorAlert($viewModel.errorMessage)
        }
    }

    private func runningSection(for entry: TimeEntry) -> some View {
        Section("Running") {
            Text(containerLabel(for: entry))
                .font(.headline)
            // No cap or warning on how long a timer has been running
            // (ticket #28's AC) — this is purely a display of elapsed time,
            // not a limit.
            Text("Started \(entry.startDate, style: .relative) ago")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("Stop") {
                    Task { await viewModel.stop() }
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel", role: .destructive) {
                    Task { await viewModel.cancel() }
                }
            }
        }
    }

    private var startSection: some View {
        Section("Start a Timer") {
            Picker("Task", selection: $taskID) {
                Text("None").tag(UUID?.none)
                ForEach(viewModel.tasks) { task in
                    Text(task.title).tag(UUID?.some(task.id))
                }
            }
            .onChange(of: taskID) { newValue in
                if newValue != nil { clearContainer(except: \Self.taskID) }
            }
            Picker("Project", selection: $projectID) {
                Text("None").tag(UUID?.none)
                ForEach(viewModel.projects) { project in
                    Text(project.name).tag(UUID?.some(project.id))
                }
            }
            .onChange(of: projectID) { newValue in
                if newValue != nil { clearContainer(except: \Self.projectID) }
            }
            Picker("Client", selection: $clientID) {
                Text("None").tag(UUID?.none)
                ForEach(viewModel.clients) { client in
                    Text(client.name).tag(UUID?.some(client.id))
                }
            }
            .onChange(of: clientID) { newValue in
                if newValue != nil { clearContainer(except: \Self.clientID) }
            }
            Picker("Course", selection: $courseID) {
                Text("None").tag(UUID?.none)
                ForEach(viewModel.courses) { course in
                    Text(course.name).tag(UUID?.some(course.id))
                }
            }
            .onChange(of: courseID) { newValue in
                if newValue != nil { clearContainer(except: \Self.courseID) }
            }

            let container = TimeEntryContainer(
                taskID: taskID, projectID: projectID, clientID: clientID, courseID: courseID
            )
            if container == nil {
                Text("Choose exactly one Task, Project, Client, or Course.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Start") {
                guard let container else { return }
                Task { await viewModel.start(container: container) }
            }
            .disabled(container == nil)
        }
    }

    /// The name of whichever Task/Project/Client/Course `entry` is attached
    /// to, looked up from the view model's already-loaded picker data —
    /// falls back to a placeholder rather than crashing if the referenced
    /// item isn't in the loaded lists. Mirrors `TimeEntriesView`'s own copy.
    private func containerLabel(for entry: TimeEntry) -> String {
        if let taskID = entry.taskID {
            return viewModel.tasks.first { $0.id == taskID }?.title ?? "Unknown Task"
        }
        if let projectID = entry.projectID {
            return viewModel.projects.first { $0.id == projectID }?.name ?? "Unknown Project"
        }
        if let clientID = entry.clientID {
            return viewModel.clients.first { $0.id == clientID }?.name ?? "Unknown Client"
        }
        if let courseID = entry.courseID {
            return viewModel.courses.first { $0.id == courseID }?.name ?? "Unknown Course"
        }
        return "Unattached"
    }

    /// Clears every container field except `keyPath` — called whenever one
    /// picker gains a non-`nil` selection, so at most one is ever set at a
    /// time (ADR-0004). Mirrors `TimeEntryFormSheet`'s own copy.
    private func clearContainer(except keyPath: PartialKeyPath<TimerView>) {
        if keyPath != \Self.taskID { taskID = nil }
        if keyPath != \Self.projectID { projectID = nil }
        if keyPath != \Self.clientID { clientID = nil }
        if keyPath != \Self.courseID { courseID = nil }
    }
}
