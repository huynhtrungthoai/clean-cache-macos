# The Homebrew cask

`Casks/cleanpilot.rb` lives in this repository, next to the release it pins. It is not a
`homebrew-*` repository of its own, so Homebrew cannot find it by name — point `brew tap` at
this repository once:

```sh
brew tap huynhtrungthoai/cleanpilot https://github.com/huynhtrungthoai/clean-cache-macos
brew install --cask huynhtrungthoai/cleanpilot/cleanpilot
```

Since Homebrew 6, non-official taps are untrusted by default. Installing by the fully
qualified name trusts just this cask; if Homebrew asks for more,
`brew trust --cask huynhtrungthoai/cleanpilot/cleanpilot` covers it and nothing else.

Once the tap exists, the usual commands work on the short name:

```sh
brew upgrade --cask cleanpilot
brew uninstall --cask cleanpilot
```

The cask also links the bundled agent CLI (`diskwise`) onto `PATH`.

## Status

The cask is **not installable yet**: `sha256` is a placeholder until the first release built
with a Developer ID certificate is published. A DMG signed ad-hoc or with a development
certificate must never be pinned here — Gatekeeper blocks it on every machine that downloads it.

## What the cask pins

| Field | Value |
|-------|-------|
| `version` | the release tag without the `v` |
| `sha256` | checksum of `CleanPilot-<version>-universal.dmg` as published on the release |
| `url` | `releases/download/v<version>/CleanPilot-<version>-universal.dmg` |
| `livecheck` | `:github_latest` against the releases page |

## Bumping it

Build the release (fails unless a Developer ID identity and notary credentials are present):

```sh
RELEASE=1 NOTARIZE=1 ARCH=universal bash build_app/build.sh
```

Then checksum the **published asset**, not a local rebuild:

```sh
shasum -a 256 CleanPilot-<version>-universal.dmg
```

GitHub also lists `digest: sha256:…` on each release asset — cross-check the two before
committing. Update `version` and `sha256` in `Casks/cleanpilot.rb` and run:

```sh
brew audit --cask --strict --online huynhtrungthoai/cleanpilot/cleanpilot
brew style --cask Casks/cleanpilot.rb
brew livecheck --cask huynhtrungthoai/cleanpilot/cleanpilot
```

`brew audit` also checks the artifact itself, so it catches a DMG that is signed ad-hoc or
has no notarization ticket stapled to it.
