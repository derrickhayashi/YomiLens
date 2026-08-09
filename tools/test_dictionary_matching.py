import gzip
from pathlib import Path
import subprocess
import tempfile
import unittest

from build_jmdict import build_database


MATCHING_FIXTURE = """<?xml version="1.0" encoding="UTF-8"?>
<JMdict created="2026-08-09" version="1.10">
  <entry>
    <ent_seq>2001</ent_seq>
    <k_ele><keb>開く</keb><ke_pri>ichi1</ke_pri></k_ele>
    <r_ele><reb>あく</reb><re_pri>ichi1</re_pri></r_ele>
    <sense><pos>Godan verb</pos><gloss>to become open</gloss></sense>
  </entry>
  <entry>
    <ent_seq>2002</ent_seq>
    <k_ele><keb>開く</keb></k_ele>
    <r_ele><reb>ひらく</reb></r_ele>
    <sense><pos>Godan verb</pos><gloss>to open something</gloss></sense>
  </entry>
  <entry>
    <ent_seq>3001</ent_seq>
    <r_ele><reb>はし</reb><re_pri>ichi1</re_pri></r_ele>
    <sense><pos>noun (common)</pos><gloss>chopsticks</gloss></sense>
  </entry>
  <entry>
    <ent_seq>3002</ent_seq>
    <r_ele><reb>はし</reb></r_ele>
    <sense><pos>Godan verb</pos><gloss>to bridge</gloss></sense>
  </entry>
  <entry>
    <ent_seq>4001</ent_seq>
    <k_ele><keb>上手</keb></k_ele>
    <r_ele><reb>じょうず</reb></r_ele>
    <r_ele><reb>うわて</reb></r_ele>
    <sense>
      <pos>adjectival noun</pos><stagr>じょうず</stagr><gloss>skillful</gloss>
    </sense>
    <sense>
      <pos>noun (common)</pos><stagr>うわて</stagr><gloss>the upper part</gloss>
    </sense>
  </entry>
  <entry>
    <ent_seq>5001</ent_seq>
    <k_ele><keb>今日</keb></k_ele>
    <k_ele><keb>今朝</keb></k_ele>
    <r_ele><reb>きょう</reb><re_restr>今日</re_restr></r_ele>
    <r_ele><reb>けさ</reb><re_restr>今朝</re_restr></r_ele>
    <sense><pos>noun (common)</pos><gloss>time expression</gloss></sense>
  </entry>
  <entry>
    <ent_seq>6001</ent_seq>
    <k_ele><keb>気がする</keb></k_ele>
    <r_ele><reb>きがする</reb></r_ele>
    <sense><pos>expression</pos><gloss>to have a feeling</gloss></sense>
  </entry>
  <entry>
    <ent_seq>6002</ent_seq>
    <k_ele><keb>手に入れる</keb></k_ele>
    <r_ele><reb>てにいれる</reb></r_ele>
    <sense><pos>expression</pos><gloss>to obtain</gloss></sense>
  </entry>
</JMdict>
"""


class DictionaryMatchingTests(unittest.TestCase):
    def test_runtime_matcher_ranks_and_applies_restrictions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "matching.xml.gz"
            database = root / "matching.sqlite3"
            executable = root / "dictionary-matcher"
            with gzip.open(archive, "wb") as fixture:
                fixture.write(MATCHING_FIXTURE.encode("utf-8"))
            build_database(archive, database, "https://example.test/matching.gz")

            repository = Path(__file__).resolve().parents[1]
            subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    str(repository / "YomiLens/DictionaryService.swift"),
                    str(repository / "tools/dictionary_matching_harness.swift"),
                    "-module-cache-path",
                    str(root / "swift-module-cache"),
                    "-o",
                    str(executable),
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            def match(surface: str, reading: str, lemma: str, pos: str):
                result = subprocess.run(
                    [executable, database, surface, reading, lemma, pos],
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout.strip()
                return result.split("\t")

            def match_expression(surface: str, reading: str, lemma: str):
                return match(surface, reading, lemma, "EXPRESSION")

            self.assertEqual(
                match("開く", "ひらく", "-", "verb")[:3],
                ["2002", "開く", "ひらく"],
            )
            self.assertEqual(
                match("はし", "はし", "-", "verb")[0],
                "3002",
            )
            upper = match("上手", "うわて", "-", "noun")
            self.assertEqual(upper[3], "noun (common)")
            self.assertEqual(upper[4], "the upper part")
            self.assertEqual(
                match("今日", "けさ", "-", "noun")[2],
                "きょう",
            )
            self.assertEqual(
                match_expression("気がする", "きがする", "-")[:3],
                ["6001", "気がする", "きがする"],
            )
            inflected_expression = match_expression(
                "手に入れた",
                "てにいれた",
                "手に入れる",
            )
            self.assertEqual(inflected_expression[0], "6002")
            self.assertEqual(inflected_expression[4], "to obtain")
            self.assertEqual(
                match_expression("気賀する", "きがする", "-")[0],
                "NO_MATCH",
            )


if __name__ == "__main__":
    unittest.main()
