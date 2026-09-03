# Releasing Copy

Pushing a version tag runs `.github/workflows/release.yml`. The workflow tests,
builds, signs, and notarizes Copy; publishes a DMG and a signed Sparkle enclosure;
then commits the updated `docs/appcast.xml` back to `main`.

The public release channel belongs to `brzvsk/Copy`. The original
`tarikbc/Copy` appcast and signing keys are intentionally not reused.

## Repository secrets

Configure these under **Settings → Secrets and variables → Actions**:

- `DEVELOPER_ID_CERT_P12_BASE64` — the Developer ID Application certificate and
  private key for Apple team `UDTBP44Q7F`, exported as `.p12` and base64 encoded.
- `DEVELOPER_ID_CERT_PASSWORD` — the temporary password used for that export.
- `SPARKLE_PRIVATE_KEY` — the private key exported from the `brzv-copy`
  Sparkle keychain account.
- `NOTARY_API_KEY_BASE64` — a base64-encoded App Store Connect API `.p8` key.
- `NOTARY_API_KEY_ID` — the API key ID.
- `NOTARY_API_ISSUER_ID` — the App Store Connect issuer ID.

`Scripts/setup-release-secrets.sh` prepares and uploads these values. Treat its
inputs and temporary files as production signing credentials; never commit them.

Run the workflow manually to verify all six secrets on a fresh GitHub runner:

```sh
gh workflow run release.yml --repo brzvsk/Copy --ref main
```

A manual run is preflight-only: it imports the certificate and validates the
Sparkle and Apple notarization credentials, but never builds, tags, or publishes.

## Development cadence

- Give each coherent feature or fix a short-lived branch. Install its local
  build for hands-on testing, then merge it into `main` only after acceptance.
- Do not bump the version or publish a release for every merged feature. Record
  user-visible changes under `Unreleased` in `CHANGELOG.md` as they land.
- Keep `main` releasable. Cut a release when several changes form a useful
  package, or immediately for a fix users should receive without waiting.
- During the `0.x` series, use a patch version for fixes only (`0.2.1`) and a
  minor version for a feature batch (`0.3.0`). Increment `CFBundleVersion` for
  every public build.
- A separate release branch is unnecessary for this workflow. Tag the exact,
  clean `main` commit selected for release.

## GitHub Pages

Serve `/docs` from `main`. The feed URL embedded in the app is:

`https://brzvsk.github.io/Copy/appcast.xml`

The first independent release uses a fresh Sparkle EdDSA key. The public key is
committed in `project.yml`; its private half is stored in the local Keychain
under `brzv-copy` and must be backed up securely before the release.

## Release ritual

1. Fetch `origin`, ensure local `main` is clean and fast-forwarded, and run:

   ```sh
   swift test --package-path CopyCore
   xcodegen generate
   xcodebuild -project Copy.xcodeproj -scheme Copy -configuration Debug CODE_SIGNING_ALLOWED=NO build
   ```

2. Bump `CFBundleShortVersionString`, `MARKETING_VERSION`, and
   `CFBundleVersion` in `project.yml`; move the accumulated `Unreleased` notes
   under the new version and date in `CHANGELOG.md`; commit.

3. Tag that exact commit and push the tag:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. Watch the Release workflow. It must finish the GitHub release and the
   appcast commit. Verify that the published DMG passes:

   ```sh
   spctl --assess --type open --context context:primary-signature -v Copy-X.Y.Z.dmg
   xcrun stapler validate Copy-X.Y.Z.dmg
   ```

5. Confirm that `https://brzvsk.github.io/Copy/appcast.xml` serves the new
   build number and that Sparkle can check for updates from the previous
   independent release.

The release workflow commits the appcast after publishing, so local `main` will
usually be one commit behind afterward. Fast-forward before starting the next
release.

## Local release dry run

With the Developer ID identity installed, run:

```sh
Scripts/release.sh X.Y.Z --dry-run
```

This builds and signs the DMG but stops before notarization and Sparkle
publication. A real release requires the notarization credentials and the
`brzv-copy` Sparkle private key.

## Homebrew

Homebrew distribution is intentionally deferred. GitHub Releases and Sparkle
are the only supported channels until a separate `brzvsk/homebrew-tap` is set
up and tested.
