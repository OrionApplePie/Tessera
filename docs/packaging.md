# Packaging

How Tessera is installed by anyone who is not building it, and what has to exist
before that works.

## Homebrew, from a tap of its own

Homebrew looks for taps by name: a repository called `homebrew-tessera` under an
account is the tap `OrionApplePie/tessera`. That is why the formula cannot simply
live here — this repository is the source, the tap is a second, tiny repository
whose only job is to hold the formula.

`Formula/tessera.rb` here is the copy that is edited; the tap gets the same file.

### Setting the tap up, once

```sh
gh repo create OrionApplePie/homebrew-tessera --public \
  --description "Homebrew tap for Tessera"

git clone https://github.com/OrionApplePie/homebrew-tessera
mkdir -p homebrew-tessera/Formula
cp Formula/tessera.rb homebrew-tessera/Formula/
cd homebrew-tessera && git add . && git commit -m "Add tessera" && git push
```

Then, from anywhere:

```sh
brew tap OrionApplePie/tessera
brew install tessera        # or --HEAD, to build main
```

### Checking the formula before pushing it

```sh
brew style Formula/tessera.rb           # style, and syntax with it
brew audit --strict --online tessera    # once the tap is installed
brew install --HEAD --verbose tessera   # the real thing, from a clean prefix
brew test tessera                       # runs the formula's own test block
```

`brew style` runs offline and catches most of what a review would.

### Cutting a release, so `--HEAD` is no longer needed

1. Tag it: `git tag v0.1.0 && git push --tags`. The version in
   `Sources/TesseraKit/App/AppInfo.swift` is what `tessera` reports about itself
   and should say the same thing.
2. Take the checksum of the tarball GitHub builds for that tag — of *that* URL and
   no other. `gh api repos/<owner>/<repo>/tarball/<tag>` returns a different
   archive: same contents, different root directory, different checksum, and
   Homebrew refuses the download. Measured on v0.1.5: 234651 bytes from the API
   against 234601 from the archive URL, and two unequal digests.

   ```sh
   curl -fsSL https://github.com/OrionApplePie/Tessera/archive/refs/tags/v0.1.0.tar.gz \
     | shasum -a 256
   ```

3. Put `url` and `sha256` into the formula, above `head`, and push the tap. The
   commented-out stanza in `Formula/tessera.rb` is where they go.

### What Homebrew core would additionally want

A formula in `homebrew/core` needs the project to be *notable* — Homebrew's own
word for "enough people use it" — as well as a tagged release, an OSI licence
and a stable tarball. The licence and the release are in hand; the rest is not
something a repository can arrange for itself, so the tap is the answer until it
is.

## What the formula does, and why

- **Builds from source.** There is no signed, notarized binary to ship, and a
  formula that builds is the honest form for a Swift package.
- **`--disable-sandbox`.** Homebrew already builds inside its own sandbox, and
  SwiftPM's refuses to write its module cache inside that.
- **Installs the binary as `tessera`.** The product is called `Tessera`; the
  command people type is lowercase, and the formula renames it on install.
- **Ships `config.example.toml`** into the formula's share directory, because
  every key is documented there and nowhere else.
- **Declares a service.** `brew services start tessera` runs `tessera run` as a
  *user agent*, not a daemon: the switcher draws on the screen and reads the
  keyboard, and a root daemon may do neither.
- **Says what to grant.** The caveats name the two permissions and where they are
  granted, and warn that macOS attributes the prompts to whatever launched the
  binary — the terminal, or Homebrew's services agent — because this is a plain
  executable rather than an app bundle.

## What this is not

Not the Mac App Store, and it cannot be: the switcher reads the window server
through a private framework for Space membership, and the App Store's sandbox
forbids that outright. Nothing here works around it — that is simply a door this
project has decided not to use.
