# Contributing

Thanks for your interest in improving Sesame. This is a small SwiftUI app; contributions of
any size are welcome.

## Getting started

```bash
git clone https://github.com/anupchavan/sesame-client-unofficial
cd sesame-client-unofficial
swift build            # or: ./scripts/bundle.sh   (assembles a signed Sesame.app)
```

Requirements: macOS 14+ and a recent Xcode/Swift toolchain. To run against your account, add
your credentials in **Settings**, or drop them in a local `secrets/` folder (gitignored).

## Project layout

```
Sources/Sesame/
  AuthManager.swift        Firebase token exchange (refresh → ID token)
  ChatClient.swift         v2 JSON-RPC WebSocket: handshake, streaming, history, calls
  ChatViewModel.swift      per-agent state + the app store
  CallManager.swift        WebRTC voice calls
  AttachmentService.swift  image/voice-note upload (CAS)
  ProfileService.swift     GET/PATCH /user + call details + feedback
  ToolKey.swift            rotating-key + encrypted secret for custom tools
  LocationProvider.swift   CoreLocation → address for session context
  ChatCache.swift          on-disk conversation cache
  Theme.swift              Obsidian Minimal palette
  Views/                   SwiftUI views
Support/                   Info.plist, entitlements
scripts/bundle.sh          build + sign + notarize
```

## Guidelines

- **Keep it lean.** No heavy dependencies; the app should stay small and fast.
- **Match the style.** Follow the surrounding code — concise, no needless abstraction.
- **Never commit secrets.** Credentials live in `secrets/` (gitignored) or Settings. Don't add
  keys, tokens, or personal data to the repo, tests, or fixtures.
- **UI changes:** keep to the Obsidian Minimal palette via `Theme`, and support light + dark.
- Test a `./scripts/bundle.sh` build and a quick run before opening a PR.

## Pull requests

1. Branch from `main`.
2. Keep PRs focused; describe what changed and why.
3. Note any new permission, entitlement, or network endpoint you introduce.

## Reporting bugs / security

Open an issue for bugs. For anything security-sensitive, follow [`SECURITY.md`](SECURITY.md)
instead of filing a public issue.
