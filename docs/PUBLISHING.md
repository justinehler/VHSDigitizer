# Publishing Checklist

Use the `VHSDigitizer` folder as the repository root. Do not publish the parent Unity project folder unless that is intentional.

## Before First GitHub Release

- Capture final screenshots and place them in `docs/screenshots/`.
- Confirm the app works on a clean Mac without Homebrew or developer tools.
- Test with the target USB capture card and at least one webcam or alternate UVC source.
- Verify camera and microphone permission prompts appear when opening the `.app`.
- Confirm recordings save correctly to a user-selected output directory.
- Confirm metadata appears in the `.mov` file and JSON sidecar.
- Confirm audio gain affects the recorded file and audio meters.
- Update `CHANGELOG.md`.

## Release Build

```sh
./build_app.sh
```

The generated app bundle is:

```text
.build/VHS Digitizer.app
```

For public downloads, sign and notarize the app before attaching it to a GitHub release.

For a local zipped artifact:

```sh
./package_release.sh
```

The generated zip is:

```text
.build/dist/VHS-Digitizer-macOS.zip
```

The build script applies an ad-hoc signature so the app bundle is internally consistent. Public downloads should still use a Developer ID certificate and Apple notarization; otherwise Gatekeeper may warn that the app is damaged or cannot be opened after download.

## GitHub Repository Hygiene

- Commit source files, docs, scripts, and assets.
- Do not commit `.build/`, generated app bundles, recordings, or local test output.
- Keep sample media out of the repo unless it is small, public-domain, and clearly licensed.

## Mac App Store Notes

The current SwiftPM app is useful for prototyping and direct distribution. A Mac App Store release should be converted into a full Xcode app project with signing, sandbox entitlements, an app icon asset catalog, archive/export settings, and security-scoped folder access.
