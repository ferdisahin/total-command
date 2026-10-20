# Homebrew packaging

`Casks/total-command.rb` packages the signed and notarized 0.2.2 universal ZIP. Its SHA-256 comes from the final release artifact. ZIP installation avoids mounting a disk image. The public tap is https://github.com/ferdisahin/homebrew-tap.

```sh
brew install --cask ferdisahin/tap/total-command
```

For a new release, run `scripts/generate-cask.sh ferdisahin total-command` after notarization and publish the matching cask to the tap. Do not replace published release files or bypass checksum checks. See `docs/DISTRIBUTION.md`.
