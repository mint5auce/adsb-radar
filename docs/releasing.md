# Building and releasing Phosphor

Phosphor uses Sparkle 2 for updates, GitHub Releases for application archives, and GitHub Pages for its signed update feed.
The source and downloads use the public `mint5auce/phosphor` repository.
The stable feed URL is `https://jon-hadley.com/phosphor/appcast.xml` unless `UPDATES_FEED_URL` is configured before distribution begins.
Keep this address working for every previously distributed version.

## Build modes

```sh
./scripts/build-app.sh
open 'build/Phosphor.app'

./scripts/build-app.sh release
open 'build/release/Phosphor.app'
```

These local builds use ad hoc signing and leave the updater disabled.
Debug previews and tests also leave update startup disabled.
Distribution builds require a Developer ID Application identity and a Sparkle public key, embed the framework and helpers, and produce a universal app at `build/distribution/Phosphor.app`.
Their symbols are written to `build/release-symbols`.
The application bundles only its own resources, not test fixtures or the separately installed `readsb` decoder.

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: Jonathan Hadley (5DS9FS8N23)'
export SPARKLE_PUBLIC_KEY='<public key from generate_keys>'
./scripts/build-app.sh release --distribution
```

Keep the app in Applications when testing installation updates.
Launching directly from a download archive or read-only volume can prevent Sparkle from replacing it.

## Signing and notarisation setup

Developer ID signing and notarisation require Apple Developer Program membership.
The Apple certificate and Sparkle EdDSA key serve different purposes and must both be retained.
Use a dedicated Sparkle keychain account for this application.
Phosphor reuses the existing key stored under `dev.mint5auce.adsb-radar`.
This keychain account is a signing credential label, independent of the new `dev.mint5auce.phosphor` bundle identifier.
Do not generate a replacement key as part of the rename.

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.mint5auce.adsb-radar
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.mint5auce.adsb-radar -p
```

Back up the private key securely using the tool's `-x` option and an appropriately protected destination outside the repository.
The exported base64 seed can be used as the GitHub `SPARKLE_PRIVATE_KEY` secret.
Keep private signing material out of source control, release assets and command output.
This application requires signed feeds and verification before extraction.
If key rotation becomes necessary, follow [Sparkle's rotation procedure](https://sparkle-project.org/documentation/#rotating-signing-keys); a Developer ID signed DMG may be needed for recovery.

For local notarisation, use a configured `notarytool` keychain profile.
The existing `wthzd-notary` profile uses the same Developer ID team and can also notarise Phosphor.
To configure a new profile using an App Store Connect API key:

```sh
xcrun notarytool store-credentials phosphor-notary \
  --key /secure/path/AuthKey.p8 \
  --key-id '<key ID>' \
  --issuer '<issuer ID>'
```

## GitHub setup

Enable GitHub Pages with GitHub Actions as its publishing source.
Create the `release` environment and require a reviewer so prepared artifacts can be inspected before publication.
The `github-pages` environment handles the subsequent feed deployment.
Only allow release tags to publish through these environments.
Protect release tags against changes and deletion.

Configure these repository variables:

| Variable | Value |
| --- | --- |
| `DEVELOPER_ID_APPLICATION` | Full signing identity name |
| `SPARKLE_PUBLIC_KEY` | Base64 public key printed by Sparkle |
| `NOTARY_KEY_ID` | App Store Connect API key ID |
| `NOTARY_ISSUER_ID` | App Store Connect issuer ID |
| `UPDATES_FEED_URL` | Optional override of the stable feed URL |

Configure these repository secrets:

| Secret | Value |
| --- | --- |
| `SIGNING_CERTIFICATE_P12` | Base64 encoding of the certificate and private key exported as P12 |
| `SIGNING_CERTIFICATE_PASSWORD` | P12 export password |
| `SPARKLE_PRIVATE_KEY` | Exported Sparkle private key file contents |
| `NOTARY_API_KEY_P8` | App Store Connect API private key file contents |

The workflow imports the certificate into a temporary keychain and removes temporary signing files after preparing the candidate.
Signing credentials are used only by the release build job, which runs on tags or manual dispatch.
Pull request checks have read-only permissions and use no release credentials.
The publish job uses the repository-scoped workflow token; a separate publishing token is unnecessary.

## Prepare a release

Update `release.json` with a stable version such as `0.2.0` and a positive numeric build number.
Increase both relative to published stable releases, including builds withdrawn from the feed.
Add authored release notes at `docs/releases/<version>.md`.
Keep those notes suitable for public readers.
Commit these inputs with the implementation.

Run the local checks:

```sh
python3 -m unittest discover -s scripts/tests
zsh -n scripts/build-app.sh scripts/package-release.sh
swift test
```

Create and push a matching release tag only when publication is authorised.
For the initial manifest, that tag is `v0.2.0`.
The Release workflow also supports manual dispatch against an existing tag.
It rejects a mismatched tag, an existing published version, a decreasing build number, and an unavailable existing feed.
The first release may bootstrap from a feed HTTP 404 only when no release has yet been published.

The workflow builds the universal app, signs nested helpers before the outer app, notarises it, staples the app's ticket, and creates the final ZIP.
It then generates the appcast with archive and feed signatures, embeds the release notes, and verifies the feed signature.
Packaging rejects mismatched signing keys before notarisation and independently verifies the archive signature using the app's embedded public key.
The `release-candidate` artifact holds the ZIP, appcast, release notes and release manifest for inspection before approving the publish job.
The separate symbols artifact supports crash diagnosis.

Publication creates a draft release, uploads the archive, manifest and signed feed without replacing existing assets, and publishes it.
It downloads the ZIP anonymously and verifies its SHA-256 before preparing the Pages artifact.
Before publication, it also verifies that the release tag still points to the source commit used to prepare the candidate.
The feed deploys afterwards and the workflow checks that its hosted bytes match the signed candidate.
Archive URLs name the exact release tag; they never use a mutable latest-download URL.
Feed entries from the preceding signed feed are retained, with no delta updates.

## Local release preparation

The packaging script prepares artifacts without uploading to GitHub.
It uploads the app privately to Apple's notarisation service.
Ensure that this submission is authorised before running it.

```sh
export NOTARY_KEYCHAIN_PROFILE=wthzd-notary
export SPARKLE_PUBLIC_KEY="$(.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.mint5auce.adsb-radar -p)"
export DEVELOPER_ID_APPLICATION='Developer ID Application: Jonathan Hadley (5DS9FS8N23)'
./scripts/package-release.sh
```

The output directory is `build/release-assets`.
Notarisation waits for up to 20 minutes and records Apple's response in `notarisation.json` in that directory.
If it times out, Apple's processing continues; use the recorded submission ID to check its status before preparing another candidate.
If it exists, move it aside before preparing a new candidate so accepted artifacts cannot be accidentally overwritten.
For an existing release stream, download and verify the current feed first and set `PREVIOUS_APPCAST` to that local file.
`SPARKLE_PRIVATE_KEY_FILE` optionally supplies an exported private key file instead of the application-specific keychain account.
For isolated staging work, `RELEASE_MANIFEST`, `RELEASE_NOTES_FILE`, `RELEASE_ASSETS_DIR` and `UPDATES_FEED_URL` can select separate inputs and destinations.
Use a separate staging key and keep staging feeds out of the production release stream.

## Manual update verification

Use two signed and notarised builds with increasing build numbers and an authorised staging feed.
Prepare the older app using `./scripts/build-app.sh release --distribution` with its staging manifest, public key and feed URL.
Prepare the newer archive using `./scripts/package-release.sh` with the next staging manifest and the same key.
Publish the newer signed archive and feed to the staging destination only after that publication is authorised.

1. Copy the older app to a writable test installation directory, quit any other Phosphor copy, and launch that copy in Synthetic mode.
2. Set a distinctive Home location and presentation preference, save them, and choose Check for Updates from the app menu.
3. Confirm that the new version and release notes appear, then install and relaunch.
4. Confirm the new version, retained preferences and cached identities, and normal radar operation.
5. Enable automatic checks and installation in Settings, close and reopen Settings, and confirm the choices persist immediately even if other settings are cancelled.
6. Repeat with Local reception and confirm the app-owned `readsb` process exits before installation and one new decoder starts after relaunch.
7. Check cancellation, offline checking, an interrupted archive download, and corrupted or wrongly signed archives and feeds.
8. Inspect the menu, update dialogs and Settings at normal and minimum window sizes.

Development builds should show a disabled Check for Updates menu item and an unavailable-updates note in Settings.
The first Phosphor version must be installed manually, including for existing ADSB Radar users.
Phosphor starts with fresh settings and caches and leaves old application data untouched.
Subsequent versions can update themselves.
Universal architecture verification does not establish execution on a physical Intel Mac.

## Recovery and metrics

If publication or Pages deployment fails, use GitHub's Re-run failed jobs so the retained, signed candidate is reused.
Retrying the publish job accepts matching existing assets but rejects different bytes and never overwrites a published archive.
Do not rebuild an already published version to repair a failed feed deployment.
The signed appcast attached to the release provides a recovery copy; verify it before deploying it.

For a locally prepared release or feed recovery, publish the verified artifacts using `scripts/github-release.py` and deploy the attached signed feed with the Recover update feed workflow.
Supply the published tag and the SHA-256 of the locally verified appcast.
This workflow downloads the public release asset, checks its hash before deployment, and checks the hosted bytes afterwards without rebuilding the application.
Run it from `main` after temporarily allowing that branch in the `github-pages` environment's deployment policies, then remove that temporary permission when the run finishes.
Keep the existing `v*` tag policy in place throughout recovery.
Publication and recovery deployment require explicit approval.

Withdraw a faulty update by removing its entry from a local copy of the feed, signing it again with Sparkle's `sign_update`, and deploying it after approval.
Keep the original release artifacts and their build number record.
Ship a correction as a new version with a higher build number.
Sparkle does not automatically downgrade installations that already updated.

GitHub's release asset API exposes download counts for each application ZIP.
Counts include repeated downloads and Sparkle update downloads and do not measure unique people, installations or active usage.
The application sends no usage heartbeat or Sparkle system profile.

```sh
gh api repos/mint5auce/phosphor/releases \
  --jq '.[] | {version: .tag_name, archives: [.assets[] | select(.name | endswith(".zip")) | {name, download_count}]}'
```
