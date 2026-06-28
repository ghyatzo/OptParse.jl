# Changelog

## [0.4.0](https://github.com/ghyatzo/OptParse.jl/compare/v0.3.0...v0.4.0) (2026-06-28)


### ⚠ BREAKING CHANGES

* redefine the @parser macro structure

### Features

* **@parser:** adds [@description](https://github.com/description) and [@footer](https://github.com/footer) syntax to [@parser](https://github.com/parser) macro ([c39db32](https://github.com/ghyatzo/OptParse.jl/commit/c39db32840a87bfac0d7638b50e127268147b1b7))
* adds "partial" passthrough pseudo parser ([b136758](https://github.com/ghyatzo/OptParse.jl/commit/b136758463cbe91888426f4da69e78121e10b458))
* **ext:** FastIdentifiers ValueParser extention ([270a972](https://github.com/ghyatzo/OptParse.jl/commit/270a972b6a56eac156981a3912e7a11f3f714074))
* **interface:** adds validation checks for user provided ([bf474f4](https://github.com/ghyatzo/OptParse.jl/commit/bf474f4488c9b197c30877b304d7a55550828aa6))
* **record:** pass parsers as keyword arguments (no named tuple). ([0cd328e](https://github.com/ghyatzo/OptParse.jl/commit/0cd328ec7e42b79e552cca0ae22b6537c3c0029b))


### Bug Fixes

* correctly handle unrecognized tokens. minor cleanups ([2197c8c](https://github.com/ghyatzo/OptParse.jl/commit/2197c8c050e5406b79f828a10e6c2860b4062f71))
* fix issue [#9](https://github.com/ghyatzo/OptParse.jl/issues/9) of incorrectly handled empty args with optionals. ([7a0cefb](https://github.com/ghyatzo/OptParse.jl/commit/7a0cefbc775b8466de33b97c0dbb35d2e5e649df))
* return correct error from no progress ([429f4bb](https://github.com/ghyatzo/OptParse.jl/commit/429f4bba0af276571e11dd47454cca908cd756c2))
* **test:** fix a test expecting the wrong error type. ([7ce7b7c](https://github.com/ghyatzo/OptParse.jl/commit/7ce7b7ca2b6ce6fbbba1daab2536e1448a4459ee))


### Refactors

* **@parser:** introduce the `lift` function to retrieve the parser ([b378e44](https://github.com/ghyatzo/OptParse.jl/commit/b378e44813e9951e3452b8b5e2647d2afdafb3eb))
* additional work on reducing precompilation ([9aa7796](https://github.com/ghyatzo/OptParse.jl/commit/9aa779617f9722141476abeaac3f36dc13c2873f))
* **api:** removes the default_metavar function. ([0c4d9f1](https://github.com/ghyatzo/OptParse.jl/commit/0c4d9f1ea64f06dc814afad06e0fab977e433c3d))
* **error:** introduce ParseError{E}, AbstractParseError, and per-parser error structs ([1240b60](https://github.com/ghyatzo/OptParse.jl/commit/1240b608a8fb744ee6e21b4f2d4e83b4ee5575f2))
* **error:** remove error traces and phase as unused. keep only subject ([388fdcb](https://github.com/ghyatzo/OptParse.jl/commit/388fdcbce0501fe5237a08ba4ad14cc6a71eaa28))
* **error:** remove the subject entirely for preparatory work. ([ed53c4f](https://github.com/ghyatzo/OptParse.jl/commit/ed53c4f98f91d80ad40ce6b706c9f62445d41029))
* **help:** new help printing layout with annotations ([67ef70a](https://github.com/ghyatzo/OptParse.jl/commit/67ef70ad4e63fa8d6421577de85b9f7fa1dd7fae))
* redefine the [@parser](https://github.com/parser) macro structure ([4a43ffb](https://github.com/ghyatzo/OptParse.jl/commit/4a43ffba0b0da6a896a59f022659c379e34a6644))
* **show:** better define a show interface and make better prints. ([6461b3c](https://github.com/ghyatzo/OptParse.jl/commit/6461b3c720037834cd276a1823b929062ce55a74))
* split dynamic/static code to help with interactive TTFP ([d5b572c](https://github.com/ghyatzo/OptParse.jl/commit/d5b572c214728aac4920f09773c44e4bcec33166))
* **test:** run tests both in dynamic and static modes ([3f66998](https://github.com/ghyatzo/OptParse.jl/commit/3f669983416c446102ff0f9056fc308a230e3f49))
* **types:** reorder parser type parameters to {T, E, S, P, R} ([850df30](https://github.com/ghyatzo/OptParse.jl/commit/850df305264fd3d0022b12350f5b43133a3f33b4))
* **usage:** adds a generic "annotations" interface, adds choices ([639876d](https://github.com/ghyatzo/OptParse.jl/commit/639876d6b80d71e4d884753d72384fe29f6c4ca9))


### Documentation

* refresh docs ([d8d4105](https://github.com/ghyatzo/OptParse.jl/commit/d8d4105578d5ff49deecfe34811a990cd1cb0d0c))
* refresh migration guide ([c172826](https://github.com/ghyatzo/OptParse.jl/commit/c172826cf14ce2f7bd5f5a04f4a6928c73462d9d))
* update docs ([7635c11](https://github.com/ghyatzo/OptParse.jl/commit/7635c11b8592e75d9f326c707d92da556bc06577))

## [0.3.0](https://github.com/ghyatzo/OptParse.jl/compare/v0.2.1...v0.3.0) (2026-05-13)


### ⚠ BREAKING CHANGES

* **str:** add an allow_empty option. defaults to false.
* **api:** rename resulttype to valuetype
* **api:** rename gate parser to switch
* **api:** merge together all the renames
* **api:** use snake case value parser keywords
* **api:** replace multiple with repeated combinators
* **api:** rename object parser to record
* **multiple:** fixed a bug where mutliple parser with min=0 failed to
* rename argparse/tryargparse to optparse/tryoptparse

### Features

* Adds automatic usage/help generation subsystem ([1e87a9f](https://github.com/ghyatzo/OptParse.jl/commit/1e87a9f164a3ea387647de6ad0369aeac250d74f))
* **api:** new trimfriendly version of construct that does not rely on ([811e60e](https://github.com/ghyatzo/OptParse.jl/commit/811e60eda520f29de88aa23ed07ca982432050f9))
* **api:** offer an automatic entry point that injects help ([33f5263](https://github.com/ghyatzo/OptParse.jl/commit/33f5263ca5d2515dc6e0638390e0f045823e27b9))
* export  generate_help and make build_helpdoc and render_helpdoc ([0dc9739](https://github.com/ghyatzo/OptParse.jl/commit/0dc9739f5c87c85d5243bd0f9d398a46c5b4f0a6))
* **help:** refactor the help rendering to be nicer. ([4d37e44](https://github.com/ghyatzo/OptParse.jl/commit/4d37e44ad50f25dc540a58fa3ce408c5a3982b86))
* **parser:** new construct parser! very wow much nice. ([cf2ae47](https://github.com/ghyatzo/OptParse.jl/commit/cf2ae4794ba875957bcc87712396473ed1df621d))
* **str:** add an allow_empty option. defaults to false. ([9d4e82e](https://github.com/ghyatzo/OptParse.jl/commit/9d4e82e84a2267d589fc176cbfda0eb3e0f330a9))


### Bug Fixes

* **docs:** fix docstrings ([e65ab5a](https://github.com/ghyatzo/OptParse.jl/commit/e65ab5a5eb3671544032870f5af297577cdbc12a))
* **docs:** updated docs and docstrings to reflect the new help system ([1516543](https://github.com/ghyatzo/OptParse.jl/commit/15165433eb8fe1a3d72f7148f53d28cee5ba0b85))
* **multiple:** fixed a bug where mutliple parser with min=0 failed to ([e7907cb](https://github.com/ghyatzo/OptParse.jl/commit/e7907cb173a43fb4d10639d3423c5d6c3a803d72))
* tighten record and sequence constructors to only accepts abstract ([bc1ada7](https://github.com/ghyatzo/OptParse.jl/commit/bc1ada7aee8ae370ec2008ef06af5cd23eca3450))
* **trim:** fix additional trimming issues with the help scoping ([3899a07](https://github.com/ghyatzo/OptParse.jl/commit/3899a07e56356c6ff776f8d1072e535b723a87ed))
* **trim:** fix focused helpdoc trimming issue in or parser. ([4447f20](https://github.com/ghyatzo/OptParse.jl/commit/4447f206a9a823076b673d833d238fd8a9b0bebd))
* **trimming:** fixed some type instabilies in the help machinery. added ([510d8da](https://github.com/ghyatzo/OptParse.jl/commit/510d8daa40fc6a92af45d2b51eccbf7870b2eb4a))


### Code Refactoring

* **api:** merge together all the renames ([10be87a](https://github.com/ghyatzo/OptParse.jl/commit/10be87a3c90735b99cd8e2b574a2420e8f24cacf))
* **api:** rename gate parser to switch ([22ec4c5](https://github.com/ghyatzo/OptParse.jl/commit/22ec4c5dffa6df62e6a66678842be51205534088))
* **api:** rename object parser to record ([dcbd8ee](https://github.com/ghyatzo/OptParse.jl/commit/dcbd8ee037a24cf783bbebcd117171c8e8ad56f2))
* **api:** rename resulttype to valuetype ([ebf7353](https://github.com/ghyatzo/OptParse.jl/commit/ebf7353993aa802888c1170a8774de5a06d41b35))
* **api:** replace multiple with repeated combinators ([ce468e5](https://github.com/ghyatzo/OptParse.jl/commit/ce468e5a7387ae3e7e91f636daf31a5d6ca5cc85))
* **api:** use snake case value parser keywords ([b050e5d](https://github.com/ghyatzo/OptParse.jl/commit/b050e5d401cc2541e86eaf3e75d875a1f7a811a8))
* rename argparse/tryargparse to optparse/tryoptparse ([2e86af7](https://github.com/ghyatzo/OptParse.jl/commit/2e86af7f1a7e3a3ef1e18a478319aea416bf4b22))

## [0.2.1](https://github.com/ghyatzo/OptParse.jl/compare/v0.2.0...v0.2.1) (2026-04-21)


### Bug Fixes

* **docs:** fix order of named_tuple object return type in docs as well ([80134bc](https://github.com/ghyatzo/OptParse.jl/commit/80134bcd9212221b8cdd04763f58c1d69d34d9e1))

## [0.2.0](https://github.com/ghyatzo/OptParse.jl/compare/v0.1.5...v0.2.0) (2026-04-05)


### ⚠ BREAKING CHANGES

* **api:** revert name change command -> cmd
* **api:** changed api names flag -> gate, switch -> flag
* **api:** changed api names objmerge -> combine, tup -> sequence
* **api:** changed api names  argument->arg, command->cmd, withDefault->default

### Features

* adds a public `resulttype` function and a hello world example ([8bbded1](https://github.com/ghyatzo/OptParse.jl/commit/8bbded19ec19719e4abd7d69b74f9b70ecb08c3b))
* **sequence:** adds constructor that accepts a tuple of parsers, not ([ffb5493](https://github.com/ghyatzo/OptParse.jl/commit/ffb54930225299dc1a350eccda9fa62c6af5119e))
* **valparsers:** adds the path value parser to match and validate pats like strings. Make all value parsers accept the metavar as positional argument ([d462689](https://github.com/ghyatzo/OptParse.jl/commit/d462689f9c5b655ad74709ad14e47a6c18d0608c))


### Bug Fixes

* **chore:** fix project references. ([bcf969d](https://github.com/ghyatzo/OptParse.jl/commit/bcf969dafba8e7f60dbd5af1b1ffd623361c87f9))
* **docs:** bad regex in docstring ([87ef205](https://github.com/ghyatzo/OptParse.jl/commit/87ef2057d856f0ab34b3f3d40c7a6b096f5a9aae))
* **docs:** change some docs to use flags instead of gate ([9266fac](https://github.com/ghyatzo/OptParse.jl/commit/9266fac0e1709a9f4bd7b11ecc732782b738ae7b))
* **docs:** documenter being difficult today ([adbaab2](https://github.com/ghyatzo/OptParse.jl/commit/adbaab26631118bab3d5aacac03d7edbd07f7366))
* **docs:** fix some docstrings ([7820592](https://github.com/ghyatzo/OptParse.jl/commit/78205920f2e11604c189f28734a1e08fca49addf))
* **docs:** forgot to add the docstrings to the manual. also some minor updates ([77b9fbd](https://github.com/ghyatzo/OptParse.jl/commit/77b9fbd95cab5b646872f09f683251a7ff6969d1))


### Code Refactoring

* **api:** changed api names  argument-&gt;arg, command-&gt;cmd, withDefault-&gt;default ([3cc88fe](https://github.com/ghyatzo/OptParse.jl/commit/3cc88fede6dabd41009e5f5d4b231f4fcfcbdcf9))
* **api:** changed api names flag -&gt; gate, switch -&gt; flag ([4e0a37d](https://github.com/ghyatzo/OptParse.jl/commit/4e0a37d92a120a933b97c6b6418397b637082b34))
* **api:** changed api names objmerge -&gt; combine, tup -&gt; sequence ([722c2ac](https://github.com/ghyatzo/OptParse.jl/commit/722c2ac23fca152f6fd069807935713b49889e9f))
* **api:** revert name change command -&gt; cmd ([d72786e](https://github.com/ghyatzo/OptParse.jl/commit/d72786ef5c1145395c1b2fa8739f3c2264036bbf))
