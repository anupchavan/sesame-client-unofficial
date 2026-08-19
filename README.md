# Sesame

A fast, native macOS client for the Sesame agents (Maya, Miles, Charlie, Simone).
SwiftUI, no Electron — a ~1.5 MB binary plus the WebRTC framework for calls. Colors follow
the [Obsidian Minimal](https://github.com/kepano/obsidian-minimal) palette and the system
appearance.

<!-- Add a screenshot here: docs/screenshot.png -->

## Features

- **Chat** with all four agents — token-streamed replies, markdown rendering, message
  history, typing/activity indicators, thumbs-up/down feedback, copy.
- **Images & voice notes** — send from the picker or drag-and-drop; incoming voice notes
  show the server transcription.
- **Voice calls** — real-time audio over WebRTC, with mute and a call timer. Call summaries
  open a details sheet.
- **Instant launch & sync** — conversations are cached locally, so launches are immediate;
  new messages (including ones sent from your phone) sync when the window regains focus, with
  native notifications when it isn't focused.
- **Profile inspector** — edit the account fields your agents read as context.
- **Custom tools (optional)** — point your agents at a personal endpoint you host to answer
  questions only your own data knows. See
  [sesame-agent-tools](https://github.com/anupchavan/sesame-agent-tools).

## Requirements

- macOS 14 (Sonoma) or newer — runs on 14, 15, and 26/27.
- To build: Xcode 15+ (Swift 5.9+). To notarize: an Apple Developer account.

## Build & run

```bash
./scripts/bundle.sh          # release build → dist/Sesame.app (signed if a Developer ID cert is present)
./scripts/bundle.sh debug    # debug build (ad-hoc signed)
```

The script builds with SwiftPM, assembles `Sesame.app`, embeds the WebRTC framework, and
code-signs it. With a `Developer ID Application` certificate it signs with the hardened
runtime; add a notarization profile (below) to also notarize and staple.

## Sign in

The app bundles Sesame's public Firebase client key (a shared identifier, not a secret), so
you usually only need to supply your own **refresh token** (`AMf…`) in **Settings (⌘,)** — it
stays on your Mac. If Sesame ever rotates that key, the app says so and you can add your own
**Firebase API key** (`AIza…`) in Settings; the "How do I find these?" walkthrough shows how
to grab either from your `app.sesame.com` session via DevTools. Values are stored in
`UserDefaults`. For development, the app also reads `secrets/api_key` / `secrets/refresh_token`
if present (that folder is gitignored). No personal credentials are baked into the app.

## How it works

Chat and calls run over the v2 JSON-RPC WebSocket (`agent-service-0`); auth is a Firebase
refresh token exchanged for short-lived ID tokens. See [`SECURITY.md`](SECURITY.md) for the
security model and [`CONTRIBUTING.md`](CONTRIBUTING.md) for the code layout.

## License

[MIT](LICENSE).
