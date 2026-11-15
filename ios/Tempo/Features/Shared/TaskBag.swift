import SwiftUI

/// Holds the unstructured tasks a screen starts from button taps so they can be cancelled when
/// the screen goes away. Starting a task under a key that is already running replaces it.
///
///     @State private var tasks = TaskBag()
///     Button("Save") { tasks.run("save") { await save() } }
///     .onDisappear { tasks.cancelAll() }
@MainActor
final class TaskBag {
    private var running: [String: Task<Void, Never>] = [:]

    init() {}

    func run(_ key: String, operation: @escaping @MainActor () async -> Void) {
        if let existing = running[key] {
            existing.cancel()
        }
        let task: Task<Void, Never> = Task { @MainActor in
            await operation()
        }
        running[key] = task
    }

    func cancel(_ key: String) {
        if let existing = running[key] {
            existing.cancel()
        }
        running[key] = nil
    }

    func cancelAll() {
        for task in running.values {
            task.cancel()
        }
        running = [:]
    }
}
