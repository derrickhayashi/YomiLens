import Foundation

@MainActor
final class DebouncedAnalysisScheduler<Result: Sendable> {
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func schedule(
        text: String,
        delayNanoseconds: UInt64,
        analyze: @escaping @Sendable (String) async -> Result,
        receive: @escaping @MainActor (String, Result) -> Void
    ) {
        task?.cancel()
        task = Task {
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            let result = await analyze(text)
            guard !Task.isCancelled else { return }
            receive(text, result)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
