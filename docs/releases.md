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
API keys and microphone setup choices are device-local and are not exported.
Subsequent release APKs use the same release key and retain app data on update.
The release workflow does not uninstall or migrate anyone's app automatically.

Local signed builds accept `VAANI_ANDROID_KEYSTORE`,
`VAANI_ANDROID_KEYSTORE_PASSWORD`, `VAANI_ANDROID_KEY_ALIAS` and
`VAANI_ANDROID_KEY_PASSWORD` through the environment. Without signing inputs,
ordinary debug builds stay unchanged; local release builds are unsigned.

## macOS signing

Current downloadable Mac builds are ad-hoc signed and **not notarized**. There
is no usable Developer ID Application identity configured for this project.
macOS Gatekeeper may require manual approval, and microphone/Accessibility
permissions can need renewal after updates. A stable Apple Developer ID and
notarization are follow-up work; do not advertise these builds as notarized.

`VAANI_SIGN_IDENTITY` selects a locally available signing identity. Release
automation currently uses ad-hoc signing. `VAANI_ARCH` selects arm64 or x86_64;
`VAANI_VERSION` and `VAANI_VERSION_CODE` stamp the packaged Info.plist without
modifying the source plist.
