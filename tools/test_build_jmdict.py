import gzip
from pathlib import Path
import sqlite3
import tempfile
import unittest

from build_jmdict import build_database, normalize_reading, normalize_spelling


FIXTURE = """<?xml version="1.0" encoding="UTF-8"?>
<JMdict created="2026-08-09" version="1.10">
  <entry>
    <ent_seq>1001</ent_seq>
    <k_ele><keb>潜む</keb><ke_pri>ichi1</ke_pri></k_ele>
    <k_ele><keb>潛む</keb></k_ele>
    <r_ele><reb>ひそむ</reb><re_pri>ichi1</re_pri></r_ele>
    <r_ele><reb>ヒソム</reb><re_restr>潛む</re_restr></r_ele>
    <sense>
      <pos>Godan verb</pos>
      <stagk>潜む</stagk>
      <stagr>ひそむ</stagr>
      <gloss>to lurk</gloss>
      <gloss g_type="fig">to be hidden</gloss>
    </sense>
    <sense><gloss>to lie dormant</gloss></sense>
  </entry>
</JMdict>
"""


class BuildJMdictTests(unittest.TestCase):
    def test_normalizes_compatibility_forms_and_reading_script(self) -> None:
        self.assertEqual(normalize_spelling("ＡＢＣ"), "ABC")
        self.assertEqual(normalize_reading("ヒソム"), "ひそむ")

    def test_builds_searchable_database_and_inherits_pos(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "fixture.xml.gz"
            output = root / "fixture.sqlite3"
            with gzip.open(archive, "wb") as fixture:
                fixture.write(FIXTURE.encode("utf-8"))

            summary = build_database(
                archive,
                output,
                "https://example.test/JMdict_e_NG.gz",
            )

            self.assertEqual(summary["entries"], 1)
            with sqlite3.connect(output) as connection:
                lookup = connection.execute(
                    "SELECT term, normalized_term, term_type "
                    "FROM lookup_terms ORDER BY term_type, term"
                ).fetchall()
                self.assertEqual(
                    lookup,
                    [
                        ("ひそむ", "ひそむ", "reading"),
                        ("ヒソム", "ヒソム", "reading"),
                        ("潛む", "潛む", "spelling"),
                        ("潜む", "潜む", "spelling"),
                    ],
                )
                parts_of_speech = connection.execute(
                    "SELECT sense_order, part_of_speech "
                    "FROM sense_parts_of_speech ORDER BY sense_order"
                ).fetchall()
                self.assertEqual(
                    parts_of_speech,
                    [(1, "Godan verb"), (2, "Godan verb")],
                )
                self.assertEqual(
                    connection.execute(
                        "SELECT reading, spelling FROM reading_restrictions"
                    ).fetchall(),
                    [("ヒソム", "潛む")],
                )
                self.assertEqual(
                    connection.execute(
                        "SELECT sense_order, spelling "
                        "FROM sense_spelling_restrictions"
                    ).fetchall(),
                    [(1, "潜む")],
                )
                self.assertEqual(
                    connection.execute(
                        "SELECT sense_order, reading "
                        "FROM sense_reading_restrictions"
                    ).fetchall(),
                    [(1, "ひそむ")],
                )
                metadata = dict(
                    connection.execute("SELECT key, value FROM metadata")
                )
                self.assertEqual(metadata["source_created"], "2026-08-09")
                self.assertEqual(metadata["source_version"], "1.10")
                self.assertEqual(metadata["schema_version"], "2")
                self.assertEqual(
                    metadata["source_license"],
                    "Creative Commons Attribution-ShareAlike 4.0",
                )


if __name__ == "__main__":
    unittest.main()
