# Security Policy

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue for anything
exploitable.

- Use [GitHub private vulnerability reporting](https://github.com/anupchavan/sesame-client-unofficial/security/advisories/new), or
- email the maintainer (see the GitHub profile).

Include steps to reproduce and the impact. We aim to acknowledge within a few days.

## Supported versions

The latest release on the default branch is supported. Older builds are not patched.

## How this app handles your data

- **Credentials stay on your device.** Your Firebase API key and refresh token are stored in
  `UserDefaults` on your Mac (or read from a gitignored `secrets/` folder in dev). They are
  sent only to Google's token endpoint and Sesame's API — never to any third party, and never
  committed to this repo.
- **No user secrets in the binary.** The app bundles only Sesame's public Firebase *client*
  key — a shared identifier present in all Sesame web traffic, used as a convenience default
  and overridable in Settings. No refresh tokens, per-user credentials, or private keys are
  baked in.
- **Chat cache** is stored unencrypted under `~/Library/Application Support/Sesame/` for fast
  launches. It contains your message text (not your credentials). Delete that folder to clear
  it.
- **Custom tool secret** (optional feature) is encrypted at rest with AES-GCM using a key held
  in the macOS Keychain; only ciphertext is written to disk.
- **Location** is requested only if you grant it, and is sent solely to your agents as
  conversation context (the same field the official app uses).
- **Microphone** is used only during voice notes and calls.

## Custom tool endpoints

Enabling a custom tool endpoint injects a rotating access key into your session so your
self-hosted endpoint can authenticate requests. Treat any text your endpoint returns as
content the model will act on, and only expose data you're comfortable sharing with whoever
holds a valid key. See
[sesame-agent-tools](https://github.com/anupchavan/sesame-agent-tools) for the threat model.

## Scope

This is an unofficial, independent client. It is not affiliated with or endorsed by Sesame.
You are responsible for complying with Sesame's terms when using it with your account.
