# YomiLens

This technical preview captures an image with the iPhone's system camera or
loads one from the photo library, runs Japanese OCR locally with Apple Vision,
draws numbered boxes around the recognized regions, shows editable recognized
text, and displays Japanese token boundaries. Each token can be tapped for a
dictionary detail sheet and saved to a persistent personal vocabulary list.

Token analysis uses Mecab-Swift 0.8.0 with its bundled IPADic dictionary. It
provides hiragana readings, dictionary forms, and parts of speech without a
network connection. The generated JMdict database adds roughly 64 MB to the
app, while the MeCab dictionary resource adds roughly 51 MB.

MeCab runs one pass for hiragana readings and a second pass that preserves
kanji in dictionary forms. This keeps results such as `潜ん → 潜む` instead of
losing the lemma spelling as `ひそむ` without degrading furigana alignment.

Dictionary matching considers the lemma, surface form, and reading together.
It normalizes compatibility characters and kana readings, ranks all plausible
JMdict entries using reading, part of speech, frequency, and preferred-form
signals, and applies JMdict's reading, spelling, and sense restrictions before
choosing the displayed meanings.

Expression matching scans adjacent tokens inside each sentence, including
particles, and tries spans up to eight tokens long. It checks both the captured
surface text and useful phrase lemma forms such as `手に入れた → 手に入れる`,
then keeps the longest non-overlapping JMdict match. Expressions receive blue
dashed underlines and their own cards; the original word cards remain available
for individual lookup.

## Run on an iPhone

1. Open `YomiLens.xcodeproj` in Xcode.
2. Connect and unlock an iPhone, then trust the Mac if prompted.
3. Select the `YomiLens` target and open **Signing & Capabilities**.
4. Choose your Apple developer team. Change the bundle identifier if Xcode says
   the current one is unavailable.
5. Select the iPhone as the run destination and press **Run**.
6. Enable Developer Mode on the iPhone if prompted.
7. On first launch, allow camera access.

The shared project has no default Apple developer team. To keep your team
selection local instead of editing the shared project, copy
`Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and
replace `YOUR_TEAM_ID` with your team ID. The local file is ignored by Git and
applies to both the app and test targets in Debug and Release. Xcode still needs
access to your signing account and certificates. If you previously selected a
team directly in Xcode, that target-level setting takes precedence; clear it to
use the local configuration.

Simulator builds do not require an Apple developer team or the local file.

After the iPhone has been paired with Xcode, enable wireless device connection
if you do not want to keep it connected by cable.

Tapping **Scan Text** opens the camera immediately. Long-press it to choose an
image from the photo library instead. Because the simulator has no camera, a
normal tap there falls back to the photo library automatically. Use a physical
iPhone to evaluate direct capture against a television.

## Build the JMdict database

The app's offline dictionary has a dependency-free Python build pipeline:

```sh
python3 tools/build_jmdict.py
```

The script downloads EDRDG's current English-only JMdict Next Generation
archive to `.cache/jmdict/` and creates
`YomiLens/Resources/JMdict.sqlite3`. Both are intentionally ignored by Git, so
run this command once after cloning and whenever the dictionary should be
refreshed. Xcode bundles the result as a read-only app resource. Refresh the
cached daily release with:

```sh
python3 tools/build_jmdict.py --force-download
```

Run the pipeline unit test with:

```sh
python3 -m unittest discover -s tools -p 'test_*.py' -v
```

Run screenshot fixtures through the real Vision → MeCab → JMdict pipeline in
an iPhone Simulator with:

```sh
xcodebuild test \
  -project YomiLens.xcodeproj \
  -scheme YomiLens \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:YomiLensTests/OCRPipelineFixtureTests \
  CODE_SIGNING_ALLOWED=NO
```

The committed fixtures under `YomiLensTests/Fixtures` contain original Japanese
text and required dictionary forms and expressions. Tests render that text into
images at runtime and run the real Vision → MeCab → JMdict pipeline without
third-party game screenshots. These synthetic images exercise clean-text OCR;
they do not reproduce television backgrounds, game fonts, or camera artifacts.
Private screenshots remain ignored and are not used by the public fixtures.

The SQLite database stores the JMdict release date, DTD version, source URL,
SHA-256 checksum, and entry count. Its normalized tables retain spellings,
readings and their restrictions, priority markers, ordered senses, inherited
parts of speech, and English glosses. It also exposes a `lookup_terms` view
indexed by written form and reading.

JMdict is updated daily and is currently distributed under CC BY-SA 4.0. The
generated database embeds the required source attribution and licence URL;
the app displays those details from its About screen. Refresh the bundled
release regularly before shipping. See the [official JMdict project](https://www.edrdg.org/jmdict/j_jmdict.html),
[archive index](https://www.edrdg.org/pub/Nihongo/00INDEX.html), and
[EDRDG licence](https://www.edrdg.org/edrdg/licence.html).

## Preview structure

- `ContentView.swift` owns the screen state and starts capture and OCR.
- `CameraPicker.swift` adapts the UIKit system camera for SwiftUI.
- `OCRService.swift` configures and runs Japanese Vision text recognition.
- `OCRDebugImageView.swift` maps Vision's normalized region coordinates onto
  the displayed photo.
- `JapaneseTokenizer.swift` performs deterministic MeCab/IPADic analysis and
  falls back to Apple Natural Language if the dictionary cannot initialize.
- `TokenListView.swift` displays recognized expressions plus token-level
  furigana, surface forms, dictionary forms, and parts of speech, preserves
  sentence and OCR line breaks, and handles phrase or token selection.
- `FuriganaPassageView.swift` renders the complete passage as natural continuous
  text with Core Text ruby annotations above kanji. Content words have dotted
  underlines, while recognized expressions have blue dashed underlines; both
  open the same dictionary sheet when tapped.
- `DictionaryService.swift` opens the bundled SQLite database read-only and
  performs ranked, lemma-first JMdict lookup.
- `DictionaryEntrySheet.swift` shows readings, meanings, and the persistent
  save/remove interaction for My List.
- `SavedVocabularyRepository.swift` serializes vocabulary mutations through an
  actor and stores complete word and expression records, including source text,
  in a versioned JSON archive under Application Support. Writes are atomic and
  protected while the device is locked. Existing `savedVocabulary.v1`
  preference data is migrated only after the new archive is verified.
- `SavedVocabularyStore.swift` exposes repository loading, failure, and saved
  item state to SwiftUI without treating unreadable data as an empty list.
- `SourcesView.swift` displays the bundled JMdict release, attribution, and
  licence link.
- `tools/build_jmdict.py` downloads and converts the English-only JMdict NG
  distribution into a compact, read-only SQLite artifact.
- `tools/dictionary_matching_harness.swift` exercises the production Swift
  matcher against generated regression dictionaries.

The preview intentionally has no sentence translation, Anki export, capture
history, custom camera, or backend. Vocabulary definitions and My List remain
fully offline at runtime.

IPADic is old and will not recognize every proper noun, game-specific term, or
modern expression. See [third-party notices](THIRD_PARTY_NOTICES.md) for Mecab-Swift, MeCab,
IPADic, and JMdict licensing and distribution requirements. Evaluate a newer
dictionary such as UniDic when improving coverage.

## License and contributions

YomiLens's original code is available under the [MIT License](LICENSE), which
allows reuse, modification, and commercial use while retaining the notice.
Third-party dependencies and dictionary data retain their own licenses; see
[third-party notices](THIRD_PARTY_NOTICES.md).

Contributions are welcome. See [contribution guidance](CONTRIBUTING.md) for
pull requests, development checks, licensing, and privacy requirements.
