# Changelog

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
