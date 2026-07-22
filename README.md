# Codex Usage Micro

**A tiny macOS menu-bar meter for Codex usage.**

See five-hour and weekly usage at a glance—without keeping a terminal open. The five-hour section appears only when Codex reports that limit for the current account.

<p align="center">
  <img src="screenshots/plenty.png" alt="Codex Usage Micro with plenty of usage remaining" width="48%">
  <img src="screenshots/low.png" alt="Codex Usage Micro with little usage remaining" width="48%">
</p>

The colored bars show **usage remaining**. The white markers show **time remaining** in each limit window. Green means usage is ahead of the clock, orange means it is behind, and red means less than 15% remains.

The menu bar uses the same compact comparison: the capsule fill shows usage remaining and its marker shows time remaining. It follows the weekly limit whenever Codex provides it, and falls back to the five-hour limit when that is the only available window.

The menu-bar item permanently stacks the `Codex` name above its usage gauge. It has no display settings or numeric percentage.

If a refresh fails while the last reading is still inside its limit window, the app keeps showing that reading and adds a small orange `S` (stale) badge next to the brand name; the tooltip and popover explain what went wrong. Definitive states — Codex not installed, or the account signed out — clear the reading instead.

## Requirements

- macOS 13 or newer
- Apple silicon
- Xcode 26 or newer command line tools (Swift 6.2)
- The ChatGPT desktop app or an authenticated Codex CLI

## Build and run

```sh
git clone https://github.com/scottdflorida/codex-usage-micro.git
cd codex-usage-micro
./build.sh
open "build/Codex Usage Micro.app"
```

No API key, server, database, package manager, or external dependency is required. The app launches the local Codex app server, reads the available five-hour and weekly rate-limit windows, and refreshes every five minutes. It sends no telemetry of its own.

To change the automatic refresh cadence, edit [`Sources/RefreshConfiguration.swift`](Sources/RefreshConfiguration.swift) and rebuild.

## Troubleshooting

- **"Codex is not installed"** — the app looks for a `codex` executable inside the ChatGPT desktop app, in the Homebrew locations, and on `PATH`. Install the ChatGPT desktop app or the Codex CLI, then press Refresh.
- **"Sign in required"** (or another account error) — the Codex app server reports usage only for an authenticated account. Sign in to the ChatGPT app, or run `codex login` in a terminal, then press Refresh.
- **The gauge shows `!`** — the last refresh failed and no valid reading remains. Hover the menu-bar item for the exact diagnostic.

## Uninstall

Quit the app from the popover, then delete the app bundle (`build/Codex Usage Micro.app`, or wherever you copied it). The app writes no preferences, caches, or other files.

## Development

The app is deliberately dependency-free. AppKit owns the menu-bar UI, while a small async client speaks newline-delimited JSON-RPC to `codex app-server --stdio`. Domain calculations and response decoding are kept independent from AppKit so they remain deterministic and testable.

The response adapter treats bucket and window names as provider-owned details. It prioritizes Codex bucket metadata, identifies supported windows by duration, tolerates additive fields, and rejects ambiguous, stale, or out-of-range values. Provider-specific changes stay contained in [`Sources/CodexResponseParser.swift`](Sources/CodexResponseParser.swift).

For local integrations, run the built executable with `--snapshot`. Output remains stable and line-oriented: `limit_0` is weekly usage and `limit_1` is five-hour usage; an unavailable window is omitted without renumbering the other one.

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
