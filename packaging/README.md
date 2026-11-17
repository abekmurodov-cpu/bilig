# Releasing Bilig

## Desktop and Android files for the website

The website's download buttons point at the newest GitHub release
(`releases/latest/download/<file>`). The **Release** workflow builds them all:

1. Raise `version:` in `pubspec.yaml` (e.g. `1.3.0+4`) and commit.
2. Tag and push: `git tag v1.3.0 && git push origin v1.3.0`.
3. GitHub builds Windows, Linux and macOS (and Android when the secrets below
   are set) and publishes a release with these files:

| File | What it is |
|---|---|
| `Bilig-Windows-Setup.exe` | Windows installer (no admin rights needed) |
| `Bilig-Windows.zip` | Windows, portable |
| `Bilig-macOS.dmg` | Mac, drag to Applications |
| `Bilig-Linux-amd64.deb` | Ubuntu / Debian / Mint |
| `Bilig-Linux-x64.tar.gz` | Any Linux, unpack and run `./bilig` |
| `Bilig-Android.apk` | Android, sideloaded |

### Android signing in CI

Add these repository secrets (Settings → Secrets and variables → Actions):

- `ANDROID_KEYSTORE_BASE64` — `base64 -i bilig-release.jks | pbcopy`
- `ANDROID_KEYSTORE_PASSWORD` — the keystore password

The keystore lives outside the repo (see the README next to it). Without these
secrets the Android build is skipped.

## Website

`website/` is published to GitHub Pages by the **Website** workflow on every
push to `main` that touches it. One-time setup: Settings → Pages → Source:
**GitHub Actions**. Address: `https://abekmurodov-cpu.github.io/bilig/`.

## Stores

### Google Play
- Google Play Console account (one-time $25).
- Upload an **App Bundle**: `flutter build appbundle` (signed with the same key).
- Use Play App Signing; keep `bilig-release.jks` as the upload key.
- Listing: icon 512×512, feature graphic 1024×500, at least 2 phone screenshots,
  short and full description, privacy policy URL (`website/privacy.html`),
  Data safety form, content rating questionnaire, target audience.
- New personal accounts must run a closed test with 12+ testers for 14 days
  before going to production.

### Apple App Store (iPhone, iPad, and optionally Mac)
- Apple Developer Program ($99/year), and a Mac with Xcode (this one works).
- In Xcode, open `ios/Runner.xcworkspace`, set the Team under Signing.
  The bundle id is `com.arximed.knowledge`.
- `flutter build ipa`, then upload with Xcode Organizer or Transporter.
- App Store Connect listing: screenshots (6.9" iPhone, 13" iPad), description,
  keywords, privacy policy URL, App Privacy answers ("Data not collected"),
  age rating, review notes (explain AI keys are optional).
- The same account lets the Mac app be **notarized**, so the .dmg opens without
  the "unidentified developer" warning, or be sold in the Mac App Store.

### Windows without the SmartScreen warning
- Either sign the installer with a code-signing certificate (Azure Trusted
  Signing is the cheapest, about $10/month), or publish to the Microsoft Store
  (free individual developer account), which signs it for you.
