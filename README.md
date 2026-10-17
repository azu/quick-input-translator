# Quick Translate Input

Translate the line or entire input field you’re writing without leaving your app. Type a trigger at the end of the line or field, and Quick Translate Input replaces it with a translation using Apple’s Translation framework.

## Get started

Requires macOS 26 or later, a compatible Xcode installation, and an Apple Development signing certificate in your keychain. No third-party dependencies or translation API keys are needed.

```sh
bash scripts/build-app.sh
open "dist/Quick Translate Input.app"
```

The build automatically uses your Apple Development certificate when exactly one is available. Otherwise, set `CODE_SIGN_IDENTITY` to the certificate’s ID. Builds keep the same signing identity, bundle identifier, and app location so Accessibility permission can survive updates. Switching from an older ad-hoc build requires granting permission once again.

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

The app is signed for local development. Developer ID distribution and notarization aren’t set up. The build refuses to silently switch to ad-hoc signing, and preserves the existing app if signing fails.

## Development

```sh
swift test
swift build
./bin/sdev lint
```

Tests cover both trigger scopes, whole-field ranges and Japanese composition, independent trigger settings and migration, native-editor Undo, language selection and persistence, replacement guards, clipboard restoration, and cancellation. Model downloads, Accessibility permission, and compatibility with external input fields also need GUI verification.

To test real Japanese-to-English translation on a physical Mac with both language models installed:

```sh
RUN_TRANSLATION_INTEGRATION=1 swift test --filter installedJapaneseEnglishModelTranslates
```

These opt-in tests check single-string translation and whole-field translation followed by native-editor replacement. They don’t download models and are skipped in normal test runs.

Start with the [project documentation](docs/README.md) for the product, requirements, and design. The design notes are currently in Japanese.
