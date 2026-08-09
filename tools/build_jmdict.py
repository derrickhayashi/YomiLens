#!/usr/bin/env python3
"""Build YomiLens's read-only SQLite dictionary from official JMdict XML."""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import sys
import urllib.request
import xml.etree.ElementTree as ET


DEFAULT_SOURCE_URL = (
    "https://www.edrdg.org/pub/Nihongo/JMdict_e_NG.gz"
)
DEFAULT_ARCHIVE = Path(".cache/jmdict/JMdict_e_NG.gz")
DEFAULT_OUTPUT = Path("YomiLens/Resources/JMdict.sqlite3")
XML_LANGUAGE = "{http://www.w3.org/XML/1998/namespace}lang"
SCHEMA_VERSION = "1"
LICENSE_NAME = "Creative Commons Attribution-ShareAlike 4.0"
LICENSE_URL = "https://www.edrdg.org/edrdg/licence.html"
ATTRIBUTION = (
    "This product uses the JMdict dictionary files. "
    "Copyright Electronic Dictionary Research and Development Group."
)


SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE entries (
    entry_id INTEGER PRIMARY KEY
);

CREATE TABLE spellings (
    entry_id INTEGER NOT NULL REFERENCES entries(entry_id),
    spelling TEXT NOT NULL,
    sort_order INTEGER NOT NULL,
    PRIMARY KEY (entry_id, spelling)
) WITHOUT ROWID;

CREATE TABLE spelling_priorities (
    entry_id INTEGER NOT NULL,
    spelling TEXT NOT NULL,
    priority TEXT NOT NULL,
    PRIMARY KEY (entry_id, spelling, priority),
    FOREIGN KEY (entry_id, spelling)
        REFERENCES spellings(entry_id, spelling)
) WITHOUT ROWID;

CREATE TABLE readings (
    entry_id INTEGER NOT NULL REFERENCES entries(entry_id),
    reading TEXT NOT NULL,
    no_kanji INTEGER NOT NULL CHECK (no_kanji IN (0, 1)),
    sort_order INTEGER NOT NULL,
    PRIMARY KEY (entry_id, reading)
) WITHOUT ROWID;

CREATE TABLE reading_priorities (
    entry_id INTEGER NOT NULL,
    reading TEXT NOT NULL,
    priority TEXT NOT NULL,
    PRIMARY KEY (entry_id, reading, priority),
    FOREIGN KEY (entry_id, reading)
        REFERENCES readings(entry_id, reading)
) WITHOUT ROWID;

CREATE TABLE reading_restrictions (
    entry_id INTEGER NOT NULL,
    reading TEXT NOT NULL,
    spelling TEXT NOT NULL,
    PRIMARY KEY (entry_id, reading, spelling),
    FOREIGN KEY (entry_id, reading)
        REFERENCES readings(entry_id, reading)
) WITHOUT ROWID;

CREATE TABLE senses (
    entry_id INTEGER NOT NULL REFERENCES entries(entry_id),
    sense_order INTEGER NOT NULL,
    PRIMARY KEY (entry_id, sense_order)
) WITHOUT ROWID;

CREATE TABLE sense_parts_of_speech (
    entry_id INTEGER NOT NULL,
    sense_order INTEGER NOT NULL,
    sort_order INTEGER NOT NULL,
    part_of_speech TEXT NOT NULL,
    PRIMARY KEY (entry_id, sense_order, sort_order),
    FOREIGN KEY (entry_id, sense_order)
        REFERENCES senses(entry_id, sense_order)
) WITHOUT ROWID;

CREATE TABLE sense_glosses (
    entry_id INTEGER NOT NULL,
    sense_order INTEGER NOT NULL,
    sort_order INTEGER NOT NULL,
    gloss TEXT NOT NULL,
    gloss_type TEXT,
    PRIMARY KEY (entry_id, sense_order, sort_order),
    FOREIGN KEY (entry_id, sense_order)
        REFERENCES senses(entry_id, sense_order)
) WITHOUT ROWID;

CREATE TABLE sense_spelling_restrictions (
    entry_id INTEGER NOT NULL,
    sense_order INTEGER NOT NULL,
    spelling TEXT NOT NULL,
    PRIMARY KEY (entry_id, sense_order, spelling),
    FOREIGN KEY (entry_id, sense_order)
        REFERENCES senses(entry_id, sense_order)
) WITHOUT ROWID;

CREATE TABLE sense_reading_restrictions (
    entry_id INTEGER NOT NULL,
    sense_order INTEGER NOT NULL,
    reading TEXT NOT NULL,
    PRIMARY KEY (entry_id, sense_order, reading),
    FOREIGN KEY (entry_id, sense_order)
        REFERENCES senses(entry_id, sense_order)
) WITHOUT ROWID;

CREATE INDEX spellings_lookup ON spellings(spelling);
CREATE INDEX readings_lookup ON readings(reading);
CREATE INDEX glosses_by_entry ON sense_glosses(entry_id, sense_order);

CREATE VIEW lookup_terms AS
SELECT spelling AS term, entry_id, 'spelling' AS term_type, sort_order
FROM spellings
UNION ALL
SELECT reading AS term, entry_id, 'reading' AS term_type, sort_order
FROM readings;
"""


def text_of(element: ET.Element | None) -> str | None:
    if element is None or element.text is None:
        return None
    value = element.text.strip()
    return value or None


def child_texts(element: ET.Element, tag: str) -> list[str]:
    return [
        value
        for child in element.findall(tag)
        if (value := text_of(child)) is not None
    ]


def download(source_url: str, archive_path: Path, force: bool) -> None:
    if archive_path.exists() and not force:
        print(f"Using cached archive: {archive_path}")
        return

    archive_path.parent.mkdir(parents=True, exist_ok=True)
    partial_path = archive_path.with_suffix(archive_path.suffix + ".part")
    request = urllib.request.Request(
        source_url,
        headers={"User-Agent": "YomiLens-JMdict-Builder/0.1"},
    )

    print(f"Downloading {source_url}")
    try:
        with urllib.request.urlopen(request) as response, partial_path.open("wb") as output:
            shutil.copyfileobj(response, output)
        os.replace(partial_path, archive_path)
    finally:
        partial_path.unlink(missing_ok=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def insert_entry(
    connection: sqlite3.Connection,
    element: ET.Element,
) -> None:
    entry_id_text = text_of(element.find("ent_seq"))
    if entry_id_text is None:
        raise ValueError("JMdict entry is missing ent_seq")
    entry_id = int(entry_id_text)
    connection.execute(
        "INSERT INTO entries(entry_id) VALUES (?)",
        (entry_id,),
    )

    for spelling_order, spelling_element in enumerate(
        element.findall("k_ele"),
        start=1,
    ):
        spelling = text_of(spelling_element.find("keb"))
        if spelling is None:
            continue
        connection.execute(
            "INSERT INTO spellings VALUES (?, ?, ?)",
            (entry_id, spelling, spelling_order),
        )
        connection.executemany(
            "INSERT OR IGNORE INTO spelling_priorities VALUES (?, ?, ?)",
            [
                (entry_id, spelling, priority)
                for priority in child_texts(spelling_element, "ke_pri")
            ],
        )

    for reading_order, reading_element in enumerate(
        element.findall("r_ele"),
        start=1,
    ):
        reading = text_of(reading_element.find("reb"))
        if reading is None:
            continue
        no_kanji = int(reading_element.find("re_nokanji") is not None)
        connection.execute(
            "INSERT INTO readings VALUES (?, ?, ?, ?)",
            (entry_id, reading, no_kanji, reading_order),
        )
        connection.executemany(
            "INSERT OR IGNORE INTO reading_priorities VALUES (?, ?, ?)",
            [
                (entry_id, reading, priority)
                for priority in child_texts(reading_element, "re_pri")
            ],
        )
        connection.executemany(
            "INSERT OR IGNORE INTO reading_restrictions VALUES (?, ?, ?)",
            [
                (entry_id, reading, spelling)
                for spelling in child_texts(reading_element, "re_restr")
            ],
        )

    inherited_parts_of_speech: list[str] = []
    for sense_order, sense_element in enumerate(
        element.findall("sense"),
        start=1,
    ):
        connection.execute(
            "INSERT INTO senses VALUES (?, ?)",
            (entry_id, sense_order),
        )

        explicit_parts_of_speech = child_texts(sense_element, "pos")
        if explicit_parts_of_speech:
            inherited_parts_of_speech = explicit_parts_of_speech
        connection.executemany(
            "INSERT INTO sense_parts_of_speech VALUES (?, ?, ?, ?)",
            [
                (entry_id, sense_order, order, part_of_speech)
                for order, part_of_speech in enumerate(
                    inherited_parts_of_speech,
                    start=1,
                )
            ],
        )

        glosses = []
        for gloss_element in sense_element.findall("gloss"):
            language = gloss_element.attrib.get(XML_LANGUAGE, "eng")
            gloss = text_of(gloss_element)
            if language in {"eng", "en"} and gloss is not None:
                glosses.append(
                    (gloss, gloss_element.attrib.get("g_type"))
                )
        connection.executemany(
            "INSERT INTO sense_glosses VALUES (?, ?, ?, ?, ?)",
            [
                (entry_id, sense_order, order, gloss, gloss_type)
                for order, (gloss, gloss_type) in enumerate(
                    glosses,
                    start=1,
                )
            ],
        )

        connection.executemany(
            "INSERT OR IGNORE INTO sense_spelling_restrictions VALUES (?, ?, ?)",
            [
                (entry_id, sense_order, spelling)
                for spelling in child_texts(sense_element, "stagk")
            ],
        )
        connection.executemany(
            "INSERT OR IGNORE INTO sense_reading_restrictions VALUES (?, ?, ?)",
            [
                (entry_id, sense_order, reading)
                for reading in child_texts(sense_element, "stagr")
            ],
        )


def build_database(
    archive_path: Path,
    output_path: Path,
    source_url: str,
    limit: int | None = None,
) -> dict[str, str | int]:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(output_path.suffix + ".building")
    temporary_path.unlink(missing_ok=True)

    connection = sqlite3.connect(temporary_path)
    root_attributes: dict[str, str] = {}
    entry_count = 0

    try:
        connection.execute("PRAGMA journal_mode = OFF")
        connection.execute("PRAGMA synchronous = OFF")
        connection.executescript(SCHEMA)

        with gzip.open(archive_path, "rb") as xml_source:
            parser = ET.iterparse(xml_source, events=("start", "end"))
            root: ET.Element | None = None

            with connection:
                for event, element in parser:
                    if root is None and event == "start":
                        root = element
                        root_attributes = dict(element.attrib)

                    if event != "end" or element.tag != "entry":
                        continue

                    insert_entry(connection, element)
                    entry_count += 1
                    element.clear()
                    if root is not None:
                        root.clear()

                    if entry_count % 25_000 == 0:
                        print(f"Parsed {entry_count:,} entries")
                    if limit is not None and entry_count >= limit:
                        break

        generated_at = dt.datetime.now(dt.timezone.utc).replace(
            microsecond=0
        ).isoformat()
        metadata = {
            "schema_version": SCHEMA_VERSION,
            "source_url": source_url,
            "source_created": root_attributes.get("created", "unknown"),
            "source_version": root_attributes.get("version", "unknown"),
            "source_sha256": sha256(archive_path),
            "source_bytes": str(archive_path.stat().st_size),
            "source_license": LICENSE_NAME,
            "source_license_url": LICENSE_URL,
            "source_attribution": ATTRIBUTION,
            "generated_at": generated_at,
            "entry_count": str(entry_count),
        }
        with connection:
            connection.executemany(
                "INSERT INTO metadata(key, value) VALUES (?, ?)",
                metadata.items(),
            )
        connection.execute("ANALYZE")
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"SQLite integrity check failed: {integrity}")
        connection.execute("VACUUM")
    except BaseException:
        connection.close()
        temporary_path.unlink(missing_ok=True)
        raise
    else:
        connection.close()
        os.replace(temporary_path, output_path)

    return {
        "output": str(output_path),
        "entries": entry_count,
        "source_created": root_attributes.get("created", "unknown"),
        "source_version": root_attributes.get("version", "unknown"),
        "database_bytes": output_path.stat().st_size,
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-url", default=DEFAULT_SOURCE_URL)
    parser.add_argument("--archive", type=Path, default=DEFAULT_ARCHIVE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--force-download",
        action="store_true",
        help="Replace the cached archive with the current daily release.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Build only the first N entries for pipeline testing.",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    if arguments.limit is not None and arguments.limit < 1:
        raise SystemExit("--limit must be a positive integer")

    download(
        arguments.source_url,
        arguments.archive,
        arguments.force_download,
    )
    summary = build_database(
        archive_path=arguments.archive,
        output_path=arguments.output,
        source_url=arguments.source_url,
        limit=arguments.limit,
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
