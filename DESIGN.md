# YomiLens — Japanese Game Dialogue Learning App

## 1. Overview

An iOS application for quickly understanding unfamiliar Japanese encountered while playing console games and capturing useful vocabulary for later study in Anki.

The primary workflow is:

PS5 dialogue
→ capture with iPhone
→ OCR
→ Japanese analysis
→ understand dialogue
→ select useful vocabulary
→ export to Anki
→ continue playing

The application is **not** a flashcard or spaced-repetition system. Anki remains responsible for storage, review, scheduling, statistics, and synchronization.

The application's responsibility is:

**Capture → Analyze → Understand → Select → Export**

The core workflow is on-device. It must not require an application backend,
account, or active network connection after required Apple language assets have
been downloaded.

The primary user is approximately JLPT N2 level: able to read substantial
Japanese, but still learning vocabulary, readings, expressions, and sentence
structure. Results should therefore be Japanese-first. Furigana and linguistic
structure are primary learning aids; English glosses and sentence translation
are optional support rather than the main product output.

---

## 2. Product Goal

The core product goal is:

> Go from encountering unknown Japanese in a game to understanding it and optionally capturing useful vocabulary for Anki in approximately five seconds.

The application will normally be used while the user is actively playing a game.

Low interaction cost is therefore more important than providing every possible linguistic feature.

The app should feel like:

1. Encounter unfamiliar Japanese.
2. Point phone at screen.
3. Capture.
4. Immediately understand the dialogue.
5. Optionally select useful vocabulary.
6. Export to Anki.
7. Resume playing.

It should not feel like stopping the game to begin a separate study session.

---

## 3. Non-Goals

The application will **not**:

- implement spaced repetition;
- implement flashcard review;
- replace Anki;
- maintain its own study schedule;
- reproduce Anki deck management;
- provide extensive learning statistics;
- attempt to become a general-purpose Japanese dictionary.

A lightweight capture history may eventually be maintained, but it is not a flashcard database or review queue.

---

## 4. Core User Flow

### 4.1 Capture

The user points the iPhone camera at Japanese dialogue displayed on a television.

The app captures an image.

### 4.2 OCR

Japanese OCR is performed locally using Apple Vision where practical.

Preferred architecture:

    Camera
      ↓
    Image
      ↓
    Apple Vision
      ↓
    Japanese text

The image should not need to leave the device merely for OCR.

### 4.3 OCR Confirmation

Recognized text is shown to the user and can be corrected.

Example:

    この先には強大な魔物が潜んでいるらしい。

This step is necessary because game fonts, backgrounds, outlines, effects, and unusual layouts may produce OCR errors.

The UI should minimize the need for correction rather than assuming OCR will always be perfect.

### 4.4 Analysis

Recognized Japanese text is passed to an analysis provider.

    AnalysisProvider.analyze(text:)

The default provider runs entirely on the iPhone and returns structured
linguistic analysis. A cloud-backed provider may be added later if real-world
testing shows that on-device quality is insufficient, but the core workflow
must not require a backend.

### 4.5 Results

The user sees:

- original Japanese;
- a continuous, naturally readable version of the complete passage with
  furigana above kanji and tappable, subtly underlined content words;
- visible token boundaries and sentence structure;
- furigana;
- relevant vocabulary;
- readings;
- dictionary forms;
- parts of speech;
- contextual definitions;
- useful expressions;
- optional natural translation.

Particles and punctuation remain visible in the continuous passage but are not
dictionary targets. They are omitted from the separate word-breakdown cards to
keep that learning view focused on meaningful vocabulary.

Example:

    この先には強大な魔物が潜んでいるらしい。

    Apparently, a powerful monster lurks ahead.

    □ 強大
      きょうだい
      powerful; mighty

    □ 魔物
      まもの
      monster

    □ 潜む
      ひそむ
      to lurk

### 4.6 Selection

The user selects vocabulary worth learning.

The app should not assume every token deserves an Anki card.

For the technical preview, tapping a token opens a compact dictionary sheet
showing its surface form, reading, lemma, part of speech, and a few English
glosses. The user can save or remove the entry from My List. Saved words and
expressions persist across launches together with the encountered form and
source passage, providing the data needed for later Anki export without turning
YomiLens into a review system.

The implementation uses a dependency-free, build-time Python pipeline that
transforms the English-only JMdict Next Generation distribution into a compact,
versioned SQLite database. Xcode bundles that generated artifact, and the app
opens it read-only to query by lemma, written form, and reading. JMdict XML is
never parsed at runtime, and the dictionary requires no backend or network
connection.

Single-word matching ranks candidates across lemma, surface form, and reading.
The score also considers exact versus normalized matches, JMdict priority
markers, and broad MeCab/JMdict part-of-speech compatibility. Before presenting
an entry, the app enforces JMdict reading-to-spelling restrictions and filters
senses by their spelling and reading restrictions.

Multiword expression matching scans adjacent tokens within a sentence while
retaining particles inside each candidate. It tries the longest spans first,
checks both captured surface text and useful final-lemma phrase forms, and keeps
non-overlapping JMdict matches. Recognized expressions appear as blue dashed
ranges in the passage and as expression cards in the breakdown. Tapping either
opens the dictionary sheet, while the individual word cards remain available.
This first deterministic pass uses the exact expression as context; ranking an
ambiguous sense from the wider sentence remains future contextual analysis.

### 4.7 Anki Export

Selected items are transformed into high-quality Anki notes.

Potential note fields:

- Expression
- Reading
- Meaning
- Example Sentence
- Example Translation
- Screenshot

Example:

    Expression:
    潜む

    Reading:
    ひそむ

    Meaning:
    to lurk

    Example Sentence:
    この先には強大な魔物が潜んでいるらしい。

    Example Translation:
    Apparently, a powerful monster lurks ahead.

    Screenshot:
    <original game image>

Anki then owns the note.

---

# 5. Japanese Language Requirements

## 5.1 Tokenization

Japanese cannot be treated as whitespace-separated text.

The analysis pipeline requires Japanese-aware morphological analysis.

Potential technologies:

- Mecab-Swift + bundled IPADic for the initial technical preview;
- Apple Natural Language as a no-reading fallback;
- MeCab + UniDic compiled for iOS;
- another native tokenizer with a bundled dictionary.

The exact implementation should remain replaceable.

---

## 5.2 Lemmatization

Flashcard candidates should generally use dictionary forms rather than the surface forms encountered in dialogue.

Example:

    Surface:
    潜んでいる

    Card:
    潜む
    ひそむ
    to lurk

The analysis model should therefore distinguish at least:

- surface form;
- lemma;
- reading.

Mecab-Swift must be invoked without transliterating the dictionary-form field.
YomiLens uses separate deterministic annotation and lemma passes so it can keep
hiragana readings while preserving the original kanji lemma. This avoids
turning a useful lookup key such as `潜む` into `ひそむ`.

---

## 5.3 Expressions

The system should recognize useful multi-word expressions.

Example:

    こんな所で油を売っている暇はないぞ！

should preferably identify:

    油を売る
    あぶらをうる
    to waste time; loaf around

rather than recommending independent cards for:

    油
    売る

Expression recognition is an important differentiator from simple OCR + dictionary lookup.

---

## 5.4 Contextual Meaning

Dictionary definitions alone may be ambiguous.

The application should present the meaning appropriate to the sentence where possible.

An on-device language model may be used to determine:

- contextual meaning;
- natural translation;
- useful expressions;
- grammatical nuance;
- whether an item is likely useful to learn.

Deterministic tools should remain responsible where practical for:

- tokenization;
- lemma generation;
- readings;
- parts of speech.

The language model should enrich linguistic analysis rather than replace the
entire linguistic pipeline. The initial implementation should use Apple's
on-device Foundation Models framework when it is available.

Model availability must be treated as a runtime capability. The app should
check whether the device is eligible, Apple Intelligence is enabled, the model
is ready, and the required locale is supported. When it is unavailable, the
app should still provide OCR, deterministic vocabulary analysis, dictionary
results, and system translation where available.

---

# 6. System Architecture

High-level architecture:

    ┌────────────────────────────────┐
    │              iOS               │
    │                                │
    │ Camera / Photos                │
    │        ↓                       │
    │ Apple Vision OCR               │
    │        ↓                       │
    │ OCR Confirmation               │
    │        ↓                       │
    │ AnalysisProvider               │
    │        ↓                       │
    │ OnDeviceAnalysisProvider       │
    │   ├─ Japanese tokenizer       │
    │   ├─ Bundled dictionary       │
    │   ├─ Translation framework    │
    │   └─ Foundation Models        │
    │        ↓                       │
    │ Results → Selection → Anki    │
    └────────────────────────────────┘

The core workflow must work without sending the screenshot or recognized text
to a server. If later evidence justifies cloud analysis, a
`CloudAnalysisProvider` can implement the same contract without changing the
views or export flow.

---

# 7. iOS Architecture

The application should remain relatively simple and state-driven.

Suggested conceptual structure:

    SwiftUI Views
          ↓
    Observable application state
          ↓
    Services
       ├── OCRService
       │      └── Apple Vision
       │
       ├── AnalysisProvider
       │      ├── OnDeviceAnalysisProvider
       │      └── CloudAnalysisProvider (optional later)
       │
       └── AnkiExportService
              └── Anki integration

Avoid unnecessary enterprise layering.

Do not introduce architectural layers simply because they are common in backend systems.

In particular, avoid automatically creating:

    View
      ↓
    ViewModel
      ↓
    Coordinator
      ↓
    UseCase
      ↓
    Repository
      ↓
    Service
      ↓
    APIClient

unless actual complexity justifies those abstractions.

Prefer SwiftUI's native state-driven model.

---

# 8. iOS Technologies

Initial technologies:

- Swift
- SwiftUI
- Apple Vision
- Apple Natural Language
- Mecab-Swift
- bundled IPADic
- SQLite
- Python build-time JMdict conversion
- PhotosPicker
- Swift structured concurrency
- Observation
- a bundled Japanese dictionary

Concepts required:

- `View`
- `@State`
- `@Binding`
- `@Environment`
- `@Observable`
- `async/await`
- `Task`
- `@MainActor`

Potential later technologies:

- AVFoundation for direct camera capture;
- SwiftData for lightweight capture history;
- Apple Translation for optional English sentence translation;
- Apple Foundation Models for optional contextual analysis;
- migration from IPADic to UniDic or another maintained dictionary if the
  preview quality justifies it;
- URLSession for an optional cloud analysis provider.

---

# 9. On-Device Analysis

Initial analysis pipeline:

    Japanese text
         ↓
    native morphological analysis
         ↓
    tokens / lemmas / readings
         ↓
    bundled dictionary lookup
         ↓
    furigana / parts of speech / vocabulary candidates
         ↓
    optional contextual / expression / translation analysis
         ↓
    structured result

MeCab tokenization and JMdict expression lookup run through a serial analysis
actor rather than on the main UI actor. Changes to editable OCR text are
debounced for 300 milliseconds. Cancelling a pending edit prevents its work
from starting, and results are applied only when they still match the current
text so an older analysis cannot overwrite a newer one.

Potential technologies:

- Mecab-Swift with bundled IPADic for initial tokenization, readings,
  lemmatization, and parts of speech;
- Apple Natural Language as a fallback when the dictionary is unavailable;
- Apple Translation for optional Japanese-to-English sentence translation;
- Apple Foundation Models for contextual meanings, expression recognition,
  usefulness ranking, and grammatical nuance;
- MeCab + UniDic compiled for iOS if IPADic does not meet the quality bar.

The implementation choice must be driven by testing with representative game
dialogue. Before introducing a backend, benchmark the on-device pipeline
against approximately 100 examples covering inflection, colloquial speech,
multi-word expressions, proper nouns, fantasy terminology, stylized dialogue,
and OCR errors.

Evaluate:

- token boundaries;
- lemma and reading accuracy;
- contextual meaning;
- expression recognition;
- translation quality;
- latency on supported devices;
- behavior without Apple Intelligence.

A backend is an optional future provider, not a prerequisite. It is justified
only if measured quality or device coverage cannot satisfy the product goal.

---

# 10. Analysis Contract

The analysis boundary should be stable regardless of its implementation:

    protocol AnalysisProvider {
        func analyze(text: String) async throws -> SentenceAnalysis
    }

Conceptual input:

    {
      "text": "この先には強大な魔物が潜んでいるらしい。"
    }

Conceptual response:

    {
      "sentence": {
        "original": "この先には強大な魔物が潜んでいるらしい。",
        "translation": "Apparently, a powerful monster lurks ahead."
      },
      "items": [
        {
          "surface": "強大な",
          "lemma": "強大",
          "reading": "きょうだい",
          "type": "adjective",
          "meaning": "powerful; mighty"
        },
        {
          "surface": "魔物",
          "lemma": "魔物",
          "reading": "まもの",
          "type": "noun",
          "meaning": "monster"
        },
        {
          "surface": "潜んでいる",
          "lemma": "潜む",
          "reading": "ひそむ",
          "type": "verb",
          "meaning": "to lurk"
        }
      ]
    }

The `SentenceAnalysis` model should be designed before significant UI
implementation so views remain independent of the linguistic implementation.
The contract should be JSON-compatible so a future cloud provider can mirror
it with `POST /analyze` without changing the rest of the app.

---

# 11. OCR

Prefer on-device OCR using Apple Vision.

Reasons:

- lower latency;
- lower bandwidth;
- no server dependency or operating cost;
- simpler system architecture;
- improved privacy;
- offline OCR.

Initial implementation should use a photo selected from the photo library rather than immediately implementing a custom camera.

This isolates OCR development from camera development.

---

# 12. Anki Integration

Anki is a downstream system.

Architecture:

    AnalysisResult
          ↓
    selected vocabulary
          ↓
    AnkiNote
          ↓
    AnkiExportService
          ↓
    Anki

The rest of the application should not depend directly on the specific Anki integration mechanism.

`AnkiExportService` provides the boundary.

The best current iOS-compatible integration mechanism should be researched before implementation.

Potential approaches include:

- Anki/AnkiMobile URL schemes;
- share/export mechanisms;
- importable files;
- other supported integration mechanisms.

The desired UX is:

    select vocabulary
          ↓
    Add to Anki
          ↓
    Done

Manual copying between applications should be avoided.

---

# 13. Context Preservation

Context is considered valuable learning information.

An Anki note should ideally preserve:

    vocabulary
        +
    reading
        +
    contextual meaning
        +
    original sentence
        +
    sentence translation
        +
    original screenshot

The screenshot may create a strong episodic association with the moment the vocabulary was encountered.

This is potentially an important product differentiator.

---

# 14. Development Strategy

Development should proceed as vertical slices.

Do not attempt to build the final application architecture upfront.

## Milestone 1 — Text Analysis

Build:

    SwiftUI text field
          ↓
    Japanese text
          ↓
    Analyze
          ↓
    OnDeviceAnalysisProvider
          ↓
    SentenceAnalysis
          ↓
    SwiftUI result

Example UI:

    ┌────────────────────────────┐
    │ この先には強大な魔物が    │
    │ 潜んでいるらしい。        │
    │                            │
    │        [ Analyze ]         │
    └────────────────────────────┘

                  ↓

    ┌────────────────────────────┐
    │ Apparently, a powerful    │
    │ monster lurks ahead.      │
    │                            │
    │ □ 強大  きょうだい        │
    │   powerful / mighty       │
    │                            │
    │ □ 魔物  まもの            │
    │   monster                 │
    │                            │
    │ □ 潜む  ひそむ            │
    │   to lurk                 │
    └────────────────────────────┘

This milestone validates:

- SwiftUI architecture;
- the analysis contract;
- on-device Japanese analysis;
- visible Japanese tokenization;
- Foundation Models availability and fallback behavior;
- result presentation.

This milestone also establishes the representative game-dialogue benchmark
described in Section 9. Its results determine whether Apple Natural Language is
sufficient or a native tokenizer and dictionary integration is required.

No camera functionality is required.

---

## Milestone 2 — Photo OCR

Add:

    PhotosPicker
         ↓
    image
         ↓
    Apple Vision
         ↓
    recognized Japanese
         ↓
    editable confirmation
         ↓
    existing analysis flow

This produces the first end-to-end version of the core product.

---

## Milestone 3 — Camera

Replace/augment photo selection with direct capture.

Target workflow:

    open app
       ↓
    point at TV
       ↓
    capture
       ↓
    OCR
       ↓
    analysis

---

## Milestone 4 — Japanese UX

Milestone 4A improves single-word dictionary matching:

- normalize compatibility characters and kana readings;
- rank lemma, surface, and reading candidates together;
- use reading, part of speech, frequency, and preferred-form signals;
- enforce JMdict reading, spelling, and sense restrictions;
- cover ambiguous and restricted entries with an executable regression suite.

Milestone 4B adds deterministic multiword expression recognition:

- scan adjacent tokens within each sentence, including internal particles;
- try surface and phrase-lemma forms over spans of up to eight tokens;
- prefer the longest non-overlapping JMdict match;
- show tappable expression ranges and cards without removing individual words;
- cover exact and inflected expression lookup in the regression suite.

Milestone 4C finishes vocabulary selection:

- persist complete word and expression records across app launches;
- retain the encountered form and source passage for later export;
- provide a real My List with detail reopening and swipe-to-delete;
- deduplicate repeated saves of the same JMdict headword and reading;
- keep the word breakdown collapsed until the user requests it;
- cover save, reload, deduplication, and removal with a regression harness.

Deeper whole-sentence sense ranking remains a later contextual-analysis step.

Improve:

- furigana rendering;
- tokenization, readings, lemmas, and parts of speech;
- expression recognition;
- vocabulary selection;
- contextual definitions;
- translation;
- handling OCR errors.

---

## Milestone 5 — Anki Export

Implement:

    select vocabulary
          ↓
    generate Anki note
          ↓
    export
          ↓
    return to game

At this point the application represents the first genuinely useful MVP.

---

## Milestone 6 — Lightweight History

Potentially store recent captures:

    Recent Captures

    Dragon Quest
    「この先には…」

    Resident Evil
    「ここから脱出…」

Purpose:

- recover previous captures;
- revisit analysis;
- export something that was not exported initially.

History must not evolve into a second flashcard/review system.

---

## Milestone 7 — Advanced Features

Only consider after the basic workflow proves useful:

- automatic dialogue-box detection;
- OCR bounding-box selection;
- tap-to-analyze regions;
- live OCR;
- automatic vocabulary usefulness ranking;
- duplicate detection against Anki;
- game/session tagging;
- grammar explanations;
- screenshot cropping;
- faster capture workflows.

---

# 15. Codex Development Strategy

Codex should be used heavily as an implementation partner.

Human responsibility:

- architecture;
- product boundaries;
- analysis contracts;
- UX decisions;
- complexity management;
- reviewing generated code.

Codex responsibility can include:

- project scaffolding;
- SwiftUI views;
- services;
- Vision integration;
- Natural Language integration;
- Translation integration;
- Foundation Models integration;
- analysis models;
- tests;
- refactoring;
- camera integration;
- Anki integration.

Example implementation tasks:

    Create a SwiftUI screen containing a Japanese text
    editor and Analyze button.

Then:

    Define AnalysisProvider and implement an on-device provider
    that returns SentenceAnalysis using async/await.

Then:

    Render SentenceAnalysis items as selectable vocabulary
    rows.

Work should be divided into small, testable vertical changes.

---

# 16. Architecture Principles

## Keep views thin

Linguistic complexity belongs behind `AnalysisProvider`, not in SwiftUI views.
Running analysis on-device does not require spreading that complexity through
the application.

## Prefer deterministic processing where possible

Tokenization, readings, lemmas and POS tagging should not unnecessarily depend
on a language model.

## Use AI where context matters

On-device language models are valuable for ambiguity, expressions, contextual
definitions, usefulness ranking, and explanation. They should enrich the
Japanese analysis rather than replace it with English. System translation may
provide an optional sentence-level reference when it is available.

## Work offline by default

After required system language assets have been downloaded, the capture and
analysis workflow should not require network access. Cloud analysis may be
added as an explicit optional provider only when evidence justifies the added
latency, privacy implications, and operating complexity.

## Optimize latency

This is an interruption-sensitive application.

## Preserve context

The sentence and screenshot are part of the learning material.

## Avoid duplicate systems

Do not rebuild functionality already provided well by Anki.

## Build vertically

A tiny working end-to-end system is preferable to several sophisticated disconnected components.

## Delay abstraction

Introduce architectural complexity only after concrete requirements justify it.

---

# 17. Primary Success Metric

The most important qualitative metric is:

> How quickly can the user go from encountering unknown Japanese on a PS5 to understanding it and optionally sending useful vocabulary to Anki without substantially interrupting the game?

Every major product and architectural decision should be evaluated against this question.
