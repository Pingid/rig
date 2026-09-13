class Rig < Formula
  desc "CLI for managing remote boxes over SSH (push, pull, run, install, tunnel)"
  homepage "https://github.com/Pingid/rig"
  url "https://github.com/Pingid/rig/releases/download/v0.1.0/rig-0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  version "0.1.0"

  def install
    libexec.install "src"
    # bin.sh resolves VERSION relative to the directory above src/.
    libexec.install "VERSION"
    libexec.install "LICENSE" if File.exist?("LICENSE")
    bin.install_symlink libexec/"src/bin.sh" => "rig"
  end

  test do
    # `rig version` needs no configuration and no network, and breaks if the
    # symlink resolution or the VERSION install path regresses.
    assert_equal version.to_s, shell_output("#{bin}/rig version").strip
    assert_match "commands", shell_output("#{bin}/rig help")
  end
end
