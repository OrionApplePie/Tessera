class Tessera < Formula
  desc "Native macOS window switcher with a map of every Space"
  homepage "https://github.com/OrionApplePie/Tessera"
  license "GPL-3.0-or-later"
  head "https://github.com/OrionApplePie/Tessera.git", branch: "main"

  # A released version goes here once a tag exists. Until then the formula is
  # installed with `--HEAD`, which builds whatever main is:
  #
  #   url "https://github.com/OrionApplePie/Tessera/archive/refs/tags/v0.1.0.tar.gz"
  #   sha256 "<shasum -a 256 of that tarball>"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :ventura

  def install
    # `--disable-sandbox` because Homebrew's own sandbox already confines the
    # build, and SwiftPM's refuses to write its cache under it.
    system "swift", "build", "--disable-sandbox", "-c", "release"

    bin.install ".build/release/Tessera" => "tessera"
    pkgshare.install "config.example.toml"
  end

  # `brew services start tessera` keeps the menu bar utility running. It is a
  # user agent rather than a daemon: the switcher draws on the screen and reads
  # the keyboard, neither of which a root daemon may do.
  service do
    run [opt_bin/"tessera", "run"]
    keep_alive true
    log_path var/"log/tessera.log"
    error_log_path var/"log/tessera.log"
  end

  def caveats
    <<~EOS
      Tessera needs two permissions before it can do anything, and it says which
      are missing at any time:

        tessera permissions

      Screen Recording lists the windows and captures their previews; without it
      the switcher is empty. Accessibility raises a particular window; without it
      only the owning application comes forward. Both are granted in
      System Settings > Privacy & Security.

      Because this is a plain binary rather than an app bundle, macOS attributes
      those prompts to whatever started it — your terminal, or Homebrew's
      services agent — so grant them to that.

      Start it:

        brew services start tessera     # keeps running, and comes back at login
        tessera run                     # or just this, in a terminal

      An example configuration, with every key documented:

        cp #{opt_pkgshare}/config.example.toml ~/.config/tessera/config.toml
    EOS
  end

  test do
    # No subcommand prints the help, which is the one thing that works without
    # any permission at all.
    assert_match "native macOS window switcher", shell_output("#{bin}/tessera")
    assert_match "Screen Recording", shell_output("#{bin}/tessera permissions")
  end
end
