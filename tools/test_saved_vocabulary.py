from pathlib import Path
import subprocess
import tempfile
import unittest


class SavedVocabularyTests(unittest.TestCase):
    def test_store_persists_deduplicates_and_removes_items(self) -> None:
        repository = Path(__file__).resolve().parents[1]

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "saved-vocabulary-harness"
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    str(repository / "YomiLens/SavedVocabularyStore.swift"),
                    str(repository / "YomiLens/AnkiExportService.swift"),
                    str(repository / "tools/saved_vocabulary_harness.swift"),
                    "-module-cache-path",
                    str(root / "swift-module-cache"),
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
                "saved vocabulary persistence ok",
            )


if __name__ == "__main__":
    unittest.main()
