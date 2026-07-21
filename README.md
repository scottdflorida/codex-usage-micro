# Codex Usage Micro

**A tiny macOS menu-bar meter for Codex usage.**

See how much weekly usage is left—and how much time remains in the limit window—without keeping a terminal open.

<p align="center">
  <img src="screenshots/plenty.png" alt="Codex Usage Micro with plenty of usage remaining" width="32%">
  <img src="screenshots/pacing.png" alt="Codex Usage Micro while usage is running ahead of the week" width="32%">
  <img src="screenshots/low.png" alt="Codex Usage Micro with little usage remaining" width="32%">
</p>

The colored bar is your **usage remaining**. The white marker is your **week remaining**. Green means usage is ahead of the clock, orange means it is behind, and red means less than 15% remains.

## Requirements

- macOS 13 or newer
- Apple silicon
- Xcode command line tools
- The ChatGPT desktop app or an authenticated Codex CLI

## Build and run

```sh
git clone https://github.com/scottdflorida/codex-usage-micro.git
cd codex-usage-micro
./build.sh
open "build/Codex Usage Micro.app"
```

No API key, server, database, package manager, or external dependency is required. The app launches the local Codex app server, reads the weekly rate-limit response, and refreshes every five minutes. It sends no telemetry of its own.

To change the automatic refresh cadence, edit [`Sources/RefreshConfiguration.swift`](Sources/RefreshConfiguration.swift) and rebuild.

## Development

The app is deliberately dependency-free. AppKit owns the menu-bar UI, while a small async client speaks newline-delimited JSON-RPC to `codex app-server --stdio`. Domain calculations and response decoding are kept independent from AppKit so they remain deterministic and testable.

Run the complete local check with:

```sh
./test.sh
./build.sh
```

`test.sh` runs strict `swift-format` lint, the dependency-free unit suite, and a full Swift 6 complete-concurrency type-check with warnings treated as errors. `build.sh` produces and verifies an ad-hoc-signed app bundle in `build/`. Both scripts run in CI on macOS.

## Privacy and security

The app launches the locally installed Codex executable and reads only the account rate-limit response. It does not accept network connections, persist account data, execute shell commands, or send telemetry of its own. The Codex process inherits the normal local Codex configuration and authentication context.

## License

[MIT](LICENSE)

Codex Usage Micro is an unofficial utility and is not affiliated with OpenAI.
