import Foundation

actor ReceivedValues {
    private var values: [String] = []
    private var analysisCount = 0

    func recordAnalysis() {
        analysisCount += 1
    }

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }

    func count() -> Int {
        analysisCount
    }
}

@main
struct AnalysisSchedulerHarness {
    static func main() async {
        let received = ReceivedValues()
        let scheduler = await MainActor.run {
            DebouncedAnalysisScheduler<String>()
        }

        await MainActor.run {
            scheduler.schedule(
                text: "cancelled-before-debounce",
                delayNanoseconds: 100_000_000,
                analyze: { value in
                    await received.recordAnalysis()
                    return value
                },
                receive: { _, value in
                    Task { await received.append(value) }
                }
            )
        }

        try? await Task.sleep(nanoseconds: 20_000_000)

        await MainActor.run {
            scheduler.schedule(
                text: "old",
                delayNanoseconds: 0,
                analyze: { value in
                    await received.recordAnalysis()
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    return value
                },
                receive: { _, value in
                    Task { await received.append(value) }
                }
            )
        }

        try? await Task.sleep(nanoseconds: 20_000_000)

        await MainActor.run {
            scheduler.schedule(
                text: "new",
                delayNanoseconds: 40_000_000,
                analyze: { value in
                    await received.recordAnalysis()
                    return value
                },
                receive: { _, value in
                    Task { await received.append(value) }
                }
            )
        }

        try? await Task.sleep(nanoseconds: 260_000_000)
        guard await received.snapshot() == ["new"] else {
            exit(2)
        }
        guard await received.count() == 2 else {
            exit(3)
        }

        print("analysis debounce and stale-result cancellation ok")
    }
}
