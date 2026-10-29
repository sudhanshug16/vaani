# Releases

Push a semantic version tag to build a **draft pre-release**:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Use the next unused version after the initial release. The Release workflow
validates the tag, checks/builds both platforms and attaches:

- `Vaani-<version>-macOS-arm64.zip` for Apple silicon.
- `Vaani-<version>-macOS-x86_64.zip` for Intel.
- `Vaani-<version>-Android.apk`, signed with the permanent Android release key.
- `SHA256SUMS`, covering all three downloads.

The workflow creates a draft only after every build passes. Review the draft's
notes/assets in GitHub Releases, then publish it when ready. It stays marked
Pre-release. Rerunning a tag may replace assets on its draft; it refuses to
overwrite a published release. Tag creation does not auto-update any device.

Versions use `major.minor.patch`; minor/patch are <=999. The Android versionCode
and Mac build number are `major * 1000000 + minor * 1000 + patch`, within
Android's positive 2,100,000,000 limit. For example, 0.1.0 uses build 1000. Tag
versions in ascending order so Android updates continue to install normally.

## Android signing

The repository uses four encrypted GitHub Actions secrets:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`. The workflow restores the keystore to runner temporary
storage and removes it after the build. Forks must supply their own secrets;
the workflow fails before packaging if any are missing.

The maintainer's private local backup is outside the checkout at
`~/Library/Application Support/Vaani/release-signing/`. Keep its keystore,
password and alias together in a private backup: replacing the key prevents
in-place updates of existing release installations. No signing material belongs
in Git or release assets.

**Existing debug installations use a different key.** Export shared settings
first; moving to the first release APK requires uninstalling the debug app,
installing the release APK, importing shared settings and re-entering API keys.
API keys and microphone setup choices are not included in file exports. Saved provider keys can be transferred using explicit paired Tailscale sync.
Subsequent release APKs use the same release key and retain app data on update.
The release workflow does not uninstall or migrate anyone's app automatically.

Local signed builds accept `VAANI_ANDROID_KEYSTORE`,
`VAANI_ANDROID_KEYSTORE_PASSWORD`, `VAANI_ANDROID_KEY_ALIAS` and
`VAANI_ANDROID_KEY_PASSWORD` through the environment. Without signing inputs,
ordinary debug builds stay unchanged; local release builds are unsigned.

## macOS signing

Mac releases use a permanent self-signed code-signing certificate. They are
**not Apple-notarized** and do not use a Developer ID certificate. Gatekeeper
may still require manual approval. No root certificate is installed or trusted.

The designated requirement binds `dev.vaani.mac` to the certificate fingerprint,
not the executable hash. Updating with the same certificate preserves that
identity. Moving from an old ad-hoc build changes identity once and may require
one final microphone/Accessibility approval. macOS permission retention still
needs verification across real updates on each machine; matching signing
requirements alone is not an end-to-end TCC test.

CI requires `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_PASSWORD`. It imports
that identity into an isolated temporary keychain, signs both architectures,
and deletes the keychain afterward. Missing secrets fail the release; there is
no silent ad-hoc fallback. Keep a private backup of the certificate and private
key: replacing them changes the app identity again.

The maintainer's local build uses the same identity from
`~/Library/Application Support/Vaani/release-signing/macos-build.keychain-db`
when present. Unlock that dedicated keychain before building if needed.
`VAANI_SIGN_IDENTITY` and `VAANI_SIGN_KEYCHAIN` can explicitly select another
identity/keychain. Other contributors without a configured identity can still
build ad-hoc locally, but should not use those builds to update a stable signed
installation. `VAANI_ARCH` selects arm64 or x86_64; `VAANI_VERSION` and
`VAANI_VERSION_CODE` stamp the packaged Info.plist without changing the source.
