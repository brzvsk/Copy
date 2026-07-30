# Releasing Copy

Pushing a version tag runs `.github/workflows/release.yml`, which builds,
signs, notarizes, and publishes a full Copy release automatically: a
Developer ID signed and notarized DMG, a signed Sparkle update zip, an
updated `docs/appcast.xml` committed back to `main`, and a GitHub release
with both artifacts attached.

This only works once the repository secrets below are configured. Each one
is set once, then reused by every future release.

## Repository secrets

Add these under **Settings -> Secrets and variables -> Actions -> New
repository secret**.

### `DEVELOPER_ID_CERT_P12_BASE64`

Base64-encoded `.p12` export of the "Developer ID Application" certificate
and its private key.

To produce it, find the certificate's name in Keychain Access (it looks like
`Developer ID Application: Your Name (TEAMID)`), then export it:

```sh
security export -k login.keychain -t identities \
  -f pkcs12 -P "<a temporary export password>" \
  -o developer-id.p12 \
  "Developer ID Application: Your Name (TEAMID)"

base64 -i developer-id.p12 | pbcopy
```

Paste the clipboard contents as the secret value. Delete `developer-id.p12`
afterward; it is a plaintext copy of a signing credential.

### `DEVELOPER_ID_CERT_PASSWORD`

The export password you chose in the `security export` command above.

### `SPARKLE_PRIVATE_KEY`

The contents of `~/copy-sparkle-private-key.txt` (see
`Scripts/sparkle-keys-README.md` for how that file was generated). Paste the
file's contents directly as the secret value.

### `NOTARY_API_KEY_BASE64`

Base64-encoded contents of an App Store Connect API key `.p8` file.

Create the key at [App Store Connect -> Users and Access -> Integrations ->
App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api),
with the "Developer" role (notarization does not need more than that). App
Store Connect only lets you download the `.p8` once, so save it immediately.
Then:

```sh
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Paste the clipboard contents as the secret value. Store the original `.p8`
somewhere durable outside the repo; you cannot re-download it from Apple.

### `NOTARY_API_KEY_ID`

The key ID shown next to the key in App Store Connect (the `XXXXXXXXXX` in
`AuthKey_XXXXXXXXXX.p8`).

### `NOTARY_API_ISSUER_ID`

The Issuer ID shown at the top of the App Store Connect API Keys page (a
UUID shared by all keys on the account).

## The release ritual

1. Bump the version (`project.yml`'s marketing version and any other version
   references) and add a `## [X.Y.Z] - YYYY-MM-DD` section to
   `CHANGELOG.md`. Commit that to `main`.
2. Tag the commit and push the tag:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

3. The workflow does the rest: archive, sign, notarize, staple, build and
   sign the Sparkle enclosure, update `docs/appcast.xml` on `main`, and
   create the GitHub release with the DMG and Sparkle zip attached.

Watch the run under the repository's **Actions** tab. If a secret is missing
or a fork triggers the workflow, the run fails immediately with a message
pointing back to this document instead of failing deep inside the pipeline.

`main` must remain pushable by `github-actions[bot]` (no branch protection
rule blocking direct pushes or requiring status checks/reviews on it), or the
workflow's appcast commit will fail at the last step and users won't see the
update even though the DMG and GitHub release were published successfully.

## GitHub Pages for the appcast

Sparkle's update feed is served from `docs/appcast.xml` via GitHub Pages.
Under **Settings -> Pages**, set the source to the `main` branch and the
`/docs` folder. Once enabled, the feed is reachable at
`https://tarikbc.github.io/Copy/appcast.xml`, which is the URL baked into
`project.yml`'s `SUFeedURL`.
