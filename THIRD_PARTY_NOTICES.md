# Third-party notices

YomiLens's original code is licensed under the [MIT License](LICENSE).
Third-party code, dictionary data, and other third-party material retain their
own licenses; the project's MIT license does not replace those terms.

## Mecab-Swift 0.8.0

- Source: [shinjukunian/Mecab-Swift](https://github.com/shinjukunian/Mecab-Swift).
- Pinned revision: `1f096492e37fc05fc2e7304091f54889974c5368`, recorded in
  `YomiLens.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Copyright (c) 2019 telethon k.k.
- License: MIT. Preserve its copyright and permission notice in copies or
  substantial portions of the software.
- Full notice: [Mecab-Swift MIT license](licenses/Mecab-Swift-MIT.txt).

The following MeCab and IPADic notices were copied without modification from
that exact dependency checkout. Review them again when updating the dependency.

## MeCab

- Included in Mecab-Swift at `Sources/mecab/mecab`.
- Copyright (c) 2001–2008, Taku Kudo.
- Copyright (c) 2004–2008, Nippon Telegraph and Telephone Corporation.
- Upstream offers GPL, LGPL, or BSD licensing; YomiLens uses the BSD option.
- Preserve the copyright, conditions, and disclaimer in source distributions
  and reproduce them in documentation or other materials accompanying binaries.
  The license also restricts using the named organization or contributors to
  endorse derived products without permission.
- Full notices: [MeCab BSD license](licenses/MeCab-BSD.txt) and
  [upstream license choice](licenses/MeCab-COPYING.txt).

## IPADic

- The app uses Mecab-Swift's `IPADic` product and bundled `ipadic dictionary`.
- Copyright 2000, 2001, 2002, 2003 Nara Institute of Science and Technology.
- License: the upstream NAIST/ICOT terms, rather than the project's MIT license.
- Copies, including modified copies, must include the copyright and accompanying
  license paragraphs. Preserve the ICOT no-warranty conditions in distributions.
- Full notice: [IPADic COPYING](licenses/IPADic-COPYING.txt), copied from
  `Sources/mecab/mecab-ipadic/COPYING` in the pinned dependency.

## JMdict / generated dictionary database

- Source: [JMdict project](https://www.edrdg.org/jmdict/j_jmdict.html).
- Copyright James William Breen and the Electronic Dictionary Research and
  Development Group (EDRDG).
- License: [Creative Commons Attribution-ShareAlike 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
- Official terms and attribution requirements:
  [EDRDG dictionary license statement](https://www.edrdg.org/edrdg/licence.html).
- `tools/build_jmdict.py` downloads the English-only distribution and transforms
  it into `YomiLens/Resources/JMdict.sqlite3`. The archive and generated database
  are ignored by Git. If distributed, the derived dictionary data retains its
  CC BY-SA 4.0 obligations; it is not covered by the project's MIT license.
- The builder embeds the release date, source URL, checksum, attribution, and
  license URL in the database. The app displays attribution and a license link
  in its About screen. Preserve these when modifying or distributing the app.
- Acknowledge JMdict in accompanying documentation, provide the official source
  and license links, identify the SQLite conversion as a transformation, and
  maintain a procedure to refresh the dictionary from current releases.

EDRDG explicitly states that software using its dictionary files does not have
to use an open-source license. The dictionary's share-alike requirements do
not by themselves change the license of YomiLens's original application code.

## Distribution checklist

Before distributing an app binary, include the Mecab-Swift, MeCab, and IPADic
license notices with that distribution (for example in bundled acknowledgements
or accompanying documentation). Repository documentation alone does not establish
that a separately distributed app includes every required notice. Retain the
JMdict About-screen attribution and links, and refresh the dictionary.

Apple frameworks are platform dependencies governed by Apple's applicable
terms; this repository does not redistribute their source code. Game dialogue,
screenshots, and other third-party media are not relicensed by this document or
by the project's MIT license. Establish permission separately before publishing
such material.
