# Sparkle EdDSA signing keys

Copy uses [Sparkle](https://sparkle-project.org) for auto-updates. Every release DMG/zip
is signed with an EdDSA keypair so the app can verify update authenticity before installing.
This keypair is generated **once** for the life of the project. This is a human-gated step,
not something to automate away.

## Generating the keypair (one time)

Sparkle ships a `generate_keys` binary inside its SPM artifact bundle. After the app has
been built at least once (so SPM has resolved and fetched Sparkle), find it with:

```sh
find ~/Library/Developer/Xcode/DerivedData -name generate_keys -path '*sparkle*' 2>/dev/null | head -1
```

(If you're building via a raw SwiftPM checkout instead of Xcode, look under
`.build/artifacts/sparkle/Sparkle/bin/generate_keys` instead.)

Run it with no arguments:

```sh
/path/to/generate_keys
```

This will:
- Generate a new EdDSA (Ed25519) keypair.
- Write the **private** key to your login keychain (item named `Private key for signing Sparkle updates for com.tarikbc.Copy`, or similar: the tool will tell you exactly what it stored).
- Print the **public** key to stdout.

Paste the printed public key into `project.yml` as the value of `SUPublicEDKey` under the
`Copy` target's `info.properties`, replacing the `"PLACEHOLDER_REPLACE_AT_KEYGEN"` placeholder.
Then run `xcodegen generate` to regenerate the Xcode project with the real key baked into
Info.plist.

## BACK UP THE PRIVATE KEY: DO NOT SKIP THIS

**The private key lives only in your login keychain by default.** If this Mac is wiped,
the keychain is lost, or you switch machines without exporting it, you will **never be able
to ship a signed update again**: every future release would need a brand new keypair, and
every already-installed copy of Copy would refuse to trust it (since it only trusts the
original `SUPublicEDKey` baked into the app it downloaded).

Immediately after generating the keys, export the private key to a file:

```sh
/path/to/generate_keys -x copy-sparkle-private.key
```

Then:
1. Store `copy-sparkle-private.key` somewhere secure and durable, **outside this git repo**
   (a password manager's secure notes/file attachments, an encrypted backup, a hardware key
   vault, anywhere except a plaintext file synced to an untrusted service).
2. Never commit this file. It is not covered by `.gitignore` by name on purpose: treat it
   like a production credential, because it is one.
3. Delete the exported copy from your working directory once it's safely stored elsewhere.

## Signing a release

Once the keypair exists (in the keychain, or restored from your backup via
`generate_keys -f copy-sparkle-private.key` if you need it on a new machine), sign each
release artifact with `sign_update` (same bin directory as `generate_keys`):

```sh
/path/to/sign_update path/to/Copy-<version>.zip
```

This prints an `edSignature` and `length` pair. Both values go into the corresponding
`<enclosure>` element of `docs/appcast.xml` for that release. Sparkle checks the signature
against `SUPublicEDKey` before installing an update, so a mismatched or missing signature
means clients will reject the update.
