# Quick Input Translator

Translate the line or entire input field you’re writing without leaving your app. Type a trigger at the end of the line or field, and Quick Input Translator replaces it with a translation using Apple’s Translation framework.

## Install

Requires an Apple Silicon Mac running macOS 26 or later. Release downloads are ad-hoc signed and aren’t notarized. The commands below verify the download checksum and remove the quarantine attribute from this app so it can be opened. Xcode and an Apple Development certificate aren’t needed for a release download.

After the first release is published, quit any running copy of Quick Input Translator and run these commands. Change `version` to the release you want:

```sh
(
  set -eu
  version=v0.1.0
  archive=quick-input-translator-macos-arm64.zip
  release_url="https://github.com/azu/quick-input-translator/releases/download/$version"
  download_dir="$(mktemp -d)"
  trap 'rm -rf "$download_dir"' EXIT
  cd "$download_dir"
  curl -fL "$release_url/$archive" -o "$archive"
  curl -fL "$release_url/$archive.sha256" -o "$archive.sha256"
  shasum -a 256 -c "$archive.sha256"
  mkdir -p "$HOME/Applications"
  ditto -x -k "$archive" "$HOME/Applications"
  xattr -dr com.apple.quarantine "$HOME/Applications/Quick Input Translator.app"
  open "$HOME/Applications/Quick Input Translator.app"
)
```

The app is installed in `~/Applications`. For an update, quit the app and repeat the commands with the new version. Because release builds use ad-hoc signing, you may need to remove and re-add the app in **System Settings → Privacy & Security → Accessibility** after updating. Language and trigger settings keep the same bundle identifier.

## Build from source

Local builds require macOS 26 or later, a compatible Xcode installation, and an Apple Development signing certificate in your keychain. No third-party dependencies or translation API keys are needed.

```sh
bash scripts/build-app.sh
open "dist/Quick Input Translator.app"
```

The build automatically uses your Apple Development certificate when exactly one is available. Otherwise, set `CODE_SIGN_IDENTITY` to the certificate’s ID. Builds keep the same signing identity, bundle identifier, and app location so Accessibility permission can survive updates. Switching from an older ad-hoc build requires granting permission once again.

The first build after the rename migrates `dist/Quick Translate Input.app` to `dist/Quick Input Translator.app` after checking the signing requirement. Your saved settings use the same bundle identifier; check Accessibility access after this one-time location change.

Quit Quick Input Translator before rebuilding. The build stops if the app is still running, so it doesn’t replace the bundle underneath a process using Accessibility access. Open the new build after the update completes.

## Set up

Open **Settings…** from the menu bar icon, or press **Command+,** while the app is active.

1. Choose the **From** and **To** languages. Available choices come from Apple’s Translation framework. The source starts as Japanese; the target defaults to your OS language. Choose **System language** to follow your OS preferences, or select a specific language. If no preferred OS language is supported, English is used. Your choices are saved between launches.
2. Click **Prepare Languages** if a download is required. Apple’s system dialog handles the download. Choose different source and target languages; unsupported pairs aren’t translated.
3. Allow **Accessibility** access to use the tool in other apps. Permission changes are detected automatically. The built-in test field works without this permission.
4. Choose a **Line-end trigger** and a **Whole-input trigger** from `...`, `;;;`, `:::`, and `@@@`. They must be different. A new setup defaults to `...` for a line and `:::` for the whole field. An existing line trigger is preserved; if it is already `:::`, the new whole-input trigger starts as `@@@`.

The interface and this README are in English. The target language setting only controls translations.

## Translate while writing

Type the selected trigger at the end of a line. The app translates that line into your chosen target language, removes the trigger, and preserves surrounding lines. It never sends or posts your text.

To translate a multiline draft, type the **Whole-input trigger** at the very end of the input field. The app passes the entire draft to the translation engine in one request, removes only the final trigger, and replaces the field in place. A whole-input trigger in an earlier line doesn’t start a translation. You don’t need to select text or switch modes.

Use the input app’s **Command+Z** immediately after replacement to undo it. Undo should restore the original field, including the trigger, as one edit. This is tested in the built-in editor; Undo behavior in external apps needs verification for each input field.

With `...` selected, Japanese IME input `。。。` and automatic substitution to `…` also work. In the built-in test field, you can type the trigger before confirming Japanese composition; no Enter key is sent. Composition support in other apps depends on the information their input fields expose.

A small spinner appears above the trigger during translation, then briefly becomes a checkmark. Failures display a reason. If the trigger’s position is unavailable, the indicator uses the cursor or pointer area instead.

**Control+Shift+A** selects the current logical line without translating it. An existing selection is preserved. You don’t need to select a line before translating.

The app doesn’t translate one or two trigger characters, four or more repeated trigger characters, triggers in the middle of a line, or triggers inserted by pasting. Wrapped text remains part of the same line until a line break.

Changing the source language, target language, or either trigger cancels an in-progress translation. Language models are prepared separately from translation; the app doesn’t start a download while you’re typing in another app.

## Input fields and limitations

The tool uses macOS Accessibility APIs to read text and selection, select the target range, and paste into the focused app. Password fields, read-only content, disconnected selections, and fields that don’t expose the required information aren’t supported.

Line translation and replacement have been verified in the built-in test field and a standard multiline input in Arc, including preservation of surrounding lines. Whole-input translation is covered by tests using the real Apple model and native text-view replacement, with a separate native Undo test. Whole-input replacement and Undo in external apps still need end-to-end verification. The paragraph-coordinate correction for richer browser editors has automated tests; end-to-end verification of that correction is still pending. Chrome, Slack, and VS Code haven’t been verified.

Terminal support is incomplete. Reading a terminal’s screen text or selection doesn’t establish the boundaries of its editable input buffer, so terminal input can’t currently be treated as an ordinary text field.

If the text, selection, or focused field changes during translation, replacement stops. After requesting a paste, the app checks the full text against the expected result. If it can’t confirm the replacement, it reports a failure without retrying or rolling back. Check the field before trying again. A focus change immediately after the final check remains a possible race, so let the operation finish before switching fields.

Pasting temporarily places the translation on the clipboard. After successful replacement, the app restores the original clipboard formats unless you copied something else in the meantime. If replacement can’t be confirmed, the translation remains on the clipboard unless another copy replaced it. Clipboard managers may observe this temporary content. Translation in the built-in test field doesn’t use the clipboard.

## Diagnostics and privacy

Expand **Diagnostics** in Settings to check shortcut registration, trigger monitoring, the time of the last input event from another app, and Secure Input status. Secure Input can block trigger detection in other apps.

To inspect diagnostic events from the last 15 minutes:

```sh
bash scripts/logs.sh
# Follow events while reproducing a problem:
bash scripts/logs.sh --stream
```

Logs record operation IDs, processing stages, app identifiers, numeric ranges, OS return codes, and whether replacement matched the expected result. Source text, translations, clipboard contents, and keystroke history aren’t logged or saved.

Local builds use your Apple Development certificate and refuse to silently switch to ad-hoc signing. Release ZIPs explicitly use ad-hoc signing. Developer ID signing and notarization aren’t set up.

## Development

```sh
swift test
swift build
bash scripts/test-version.sh
./bin/sdev lint
```

Tests cover both trigger scopes, whole-field ranges and Japanese composition, independent trigger settings and migration, native-editor Undo, language selection and persistence, replacement guards, clipboard restoration, and cancellation. Model downloads, Accessibility permission, and compatibility with external input fields also need GUI verification.

To test real Japanese-to-English translation on a physical Mac with both language models installed:

```sh
RUN_TRANSLATION_INTEGRATION=1 swift test --filter installedJapaneseEnglishModelTranslates
```

These opt-in tests check single-string translation and whole-field translation followed by native-editor replacement. They don’t download models and are skipped in normal test runs.

Start with the [project documentation](docs/README.md) for the product, requirements, and design. The design notes are currently in Japanese.

## Releases

`VERSION` is the source for the app version and release tag. Versions use `MAJOR.MINOR.PATCH`; tags use `vMAJOR.MINOR.PATCH`.

Run **Create Release PR** in GitHub Actions on `main` and enter a version greater than `VERSION`. The workflow changes only `VERSION` and opens a `release/v…` PR. Review and merge that PR to create the tag, run tests on macOS 26, and publish the Apple Silicon ZIP and SHA-256 checksum. Enable **Settings → Actions → General → Allow GitHub Actions to create and approve pull requests** if PR creation is disabled.

You can also release the current version by pushing its matching tag, including the first release:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The **Release** workflow also accepts an existing tag through manual dispatch for retries. It refuses a tag that differs from `VERSION`. Assets are attached to a draft before publication; a retry can replace assets in a draft, but doesn’t overwrite an already published release. Both workflows use `GITHUB_TOKEN`; no signing secrets or personal access token are required. If a bot merges the release PR using `GITHUB_TOKEN`, create and push the matching tag yourself, because that merge event won’t start another workflow.

To package a release locally without modifying the certificate-signed app in `dist`:

```sh
bash scripts/package-release.sh
```
