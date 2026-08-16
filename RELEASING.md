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

### `HOMEBREW_TAP_DEPLOY_KEY`

The private half of an SSH deploy key with write access to
[`tarikbc/homebrew-tap`](https://github.com/tarikbc/homebrew-tap), which is
what `brew install --cask tarikbc/tap/copy` reads. The release workflow uses
it to push the cask version bump.

The workflow's built-in `github.token` is scoped to this repository and
cannot write to the tap, so this needs its own credential. A deploy key is
narrower than a personal access token: it grants write to that one repository
instead of everything the account can reach, and it does not expire.

To rotate it:

```sh
ssh-keygen -t ed25519 -f tap-deploy-key -N "" -C "copy-release-tap-bot"

# Register the PUBLIC half on the tap, with write access.
gh api -X POST /repos/tarikbc/homebrew-tap/keys \
  -f title="copy-release-tap-bot" \
  -f key="$(cat tap-deploy-key.pub)" \
  -F read_only=false

# Store the PRIVATE half here.
gh secret set HOMEBREW_TAP_DEPLOY_KEY --repo tarikbc/Copy < tap-deploy-key

rm -f tap-deploy-key tap-deploy-key.pub
```

Delete the old key at
[the tap's deploy key settings](https://github.com/tarikbc/homebrew-tap/settings/keys)
afterward. If the secret is missing the release still succeeds; it logs a skip
and the tap stays on its previous version until someone bumps it by hand.

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

Always `git pull` before you bump the version and tag. The previous release's
appcast commit is made by the bot, so your local `main` is a commit behind
after every release. Tagging on top of a stale `main` is what produced the
half-published v0.1.5 described below.

## Recovering a half-published release

The appcast commit is the LAST step, so a failure there leaves a release that
looks published (the GitHub release, the DMG, and the Sparkle zip are all
live and correctly signed) while no existing user is ever offered the update,
because Sparkle only reads `docs/appcast.xml`. The Actions run is red but the
artifacts are fine, so do not re-tag and do not rebuild.

Re-running the failed job does not help: a tag push runs the workflow file as
it existed *at that tag*, so a fix landed on `main` afterward is not used.

Repair the appcast by hand instead. The signature is EdDSA over the published
zip and Ed25519 is deterministic, so signing the release artifact locally with
the same key reproduces exactly what CI would have written:

```sh
gh release download vX.Y.Z -p "Copy-X.Y.Z.zip" -D /tmp

# Same key CI uses, read from the `copy` keychain account.
SIGN=~/Library/Developer/Xcode/DerivedData/Copy-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update
$SIGN --account copy /tmp/Copy-X.Y.Z.zip
```

Paste the printed `sparkle:edSignature` and `length` into a new leading
`<item>` in `docs/appcast.xml`, copying the shape of the entry below it.
`sparkle:version` is the build number (`CFBundleVersion`), which is what
Sparkle actually compares, and the enclosure URL must point at the **zip**,
never the DMG. Then repoint the site's download buttons and commit both:

```sh
sed -i.bak "s|releases/download/v[0-9][0-9.]*/Copy-[0-9][0-9.]*\.dmg|releases/download/vX.Y.Z/Copy-X.Y.Z.dmg|g" docs/index.html
rm -f docs/index.html.bak
```

Verify before trusting it, including that the check can actually fail:

```sh
$SIGN --account copy --verify /tmp/Copy-X.Y.Z.zip "<the signature>"; echo "exit: $?"   # 0
$SIGN --account copy --verify /tmp/Copy-X.Y.Z.zip "AA<wrong signature>"                # must error
```

The `length` must equal the release asset's byte count exactly, and the
keychain's public key must match `SUPublicEDKey` in `project.yml`
(`generate_keys --account copy -p` prints it). After pushing, confirm
`https://tarikbc.github.io/Copy/appcast.xml` actually serves the new version;
GitHub Pages takes a minute or two.

The tap bump runs after the appcast step and pushes to a different repository,
so it can fail on its own. Recover that with `brew` untouched: checksum the
published DMG (`shasum -a 256`) and edit `version` and `sha256` in the tap's
`Casks/copy.rb`.

## GitHub Pages for the appcast

Sparkle's update feed is served from `docs/appcast.xml` via GitHub Pages.
Under **Settings -> Pages**, set the source to the `main` branch and the
`/docs` folder. Once enabled, the feed is reachable at
`https://tarikbc.github.io/Copy/appcast.xml`, which is the URL baked into
`project.yml`'s `SUFeedURL`.
