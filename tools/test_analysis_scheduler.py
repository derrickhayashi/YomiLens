from pathlib import Path
import subprocess
import tempfile
import unittest


class AnalysisSchedulerTests(unittest.TestCase):
    def test_debounce_drops_cancelled_stale_results(self) -> None:
        repository = Path(__file__).resolve().parents[1]

        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "analysis-scheduler-harness"
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    str(repository / "YomiLens/DebouncedAnalysisScheduler.swift"),
                    str(repository / "tools/analysis_scheduler_harness.swift"),
                    "-module-cache-path",
                    str(Path(directory) / "swift-module-cache"),
                    "-o",
                    str(executable),
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            result = subprocess.run(
                [executable],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                result.stdout.strip(),
                "analysis debounce and stale-result cancellation ok",
            )


if __name__ == "__main__":
    unittest.main()
