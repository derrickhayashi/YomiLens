# YomiLens

This technical preview opens the iPhone's system camera, captures one photo,
runs Japanese OCR locally with Apple Vision, draws numbered boxes around the
recognized regions, shows editable recognized text, and displays Apple Natural
Language's Japanese token boundaries. Each token can be tapped for a dictionary
detail sheet and marked as a word to learn.

Token analysis uses Mecab-Swift 0.8.0 with its bundled IPADic dictionary. It
provides hiragana readings, dictionary forms, and parts of speech without a
network connection. The current debug app is approximately 55 MB, primarily
because the dictionary resource is approximately 51 MB.

## Run on an iPhone

1. Open `YomiLens.xcodeproj` in Xcode.
2. Connect and unlock an iPhone, then trust the Mac if prompted.
3. Select the `YomiLens` target and open **Signing & Capabilities**.
4. Choose your Apple developer team. Change the bundle identifier if Xcode says
   the current one is unavailable.
5. Select the iPhone as the run destination and press **Run**.
6. Enable Developer Mode on the iPhone if prompted.
7. On first launch, allow camera access.

After the iPhone has been paired with Xcode, enable wireless device connection
if you do not want to keep it connected by cable.

The simulator can build and display the initial screen, but the scan button
reports that no camera is available. Use a physical iPhone to evaluate OCR
against a television.

## Preview structure

- `ContentView.swift` owns the screen state and starts capture and OCR.
- `CameraPicker.swift` adapts the UIKit system camera for SwiftUI.
- `OCRService.swift` configures and runs Japanese Vision text recognition.
- `OCRDebugImageView.swift` maps Vision's normalized region coordinates onto
  the displayed photo.
- `JapaneseTokenizer.swift` performs deterministic MeCab/IPADic analysis and
  falls back to Apple Natural Language if the dictionary cannot initialize.
- `TokenListView.swift` displays token-level furigana, surface forms, dictionary
  forms, and parts of speech, preserves sentence and OCR line breaks, and
  handles token selection.
- `FuriganaPassageView.swift` renders the complete passage as natural continuous
  text with Core Text ruby annotations above kanji. Content words have dotted
  underlines and open the same dictionary sheet when tapped.
- `DictionaryService.swift` provides the deliberately small, replaceable preview
  lexicon and lemma-first lookup.
- `DictionaryEntrySheet.swift` shows readings, meanings, and the session-only
  "Learn this word" interaction.

The preview intentionally has no sentence translation, persistent learning
list, custom camera, or backend. Its vocabulary definitions come from a tiny
hand-authored starter lexicon, not yet the planned JMdict database.

IPADic is old and will not recognize every proper noun, game-specific term, or
modern expression. Before distribution, review the licenses of Mecab-Swift,
MeCab, and the bundled dictionary and evaluate a newer dictionary such as
UniDic.
