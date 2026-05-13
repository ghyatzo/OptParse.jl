# Changelog

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
