# Codex Usage Micro

## A tiny macOS menu-bar meter for Codex usage.
- No API key or separate login required
- No third-party dependencies
- I have a job watching Codex release notes so I can update when OpenAI changes how usage data is exposed

***Get the companion meters for [Cursor/Grok](https://github.com/scottdflorida/cursor-usage-micro) and
[Claude](https://github.com/scottdflorida/claude-usage-micro)!*** *(So you can always see which services still have
usage remaining.)*  
<img width="470" height="37" alt="image" src="https://github.com/user-attachments/assets/99cdc56b-7ca3-4a0d-8a10-9dd10f2d9f45" /> 

The purpose is to show you **how your usage is draining compared to the time left in each limit window**.  
The vertical marker inside the meter moves from right to left as the window progresses.  
The fill drains as usage is consumed.
- Green when remaining usage exceeds remaining time
- Amber when remaining usage is less than remaining time
- Red when remaining usage is less than 15%

The menu-bar gauge follows weekly usage when available and falls back to the five-hour limit when it is the only
readable window. The five-hour limit appears only when Codex reports it for the current account.

In the menu bar: meter at a glance  
<img width="68" height="36" alt="image" src="https://github.com/user-attachments/assets/d0a23a3f-1915-4c5f-98fc-8137a1c3988a" />

On hover: the data that matters  
<img width="275" height="66" alt="image" src="https://github.com/user-attachments/assets/a469b206-3372-43f7-9e7b-0a4199eb5579" />

On click: the full view  
<img width="365" height="212" alt="image" src="https://github.com/user-attachments/assets/e0585574-7b6d-4eb4-a7c4-567db690fc27" />

## Requirements

- macOS 13 or newer
- Apple silicon or Intel; the build targets the host architecture
- A Swift 6.2-capable Xcode toolchain (Xcode 26 or newer)
- The ChatGPT desktop app or an authenticated Codex CLI

## Build and run

```sh
git clone https://github.com/scottdflorida/codex-usage-micro.git
cd codex-usage-micro
./build.sh
open "build/Codex Usage Micro.app"
```

No API key, hosted service, app-owned database, package manager, or third-party dependency is required. The app
launches the local Codex app server, reads the available five-hour and weekly rate-limit windows, and refreshes every
five minutes.
It sends no telemetry of its own.

To change the automatic refresh cadence, edit [`Sources/RefreshConfiguration.swift`](Sources/RefreshConfiguration.swift)
and rebuild.

## Development

Run the strict local checks and build with:

```sh
./test.sh
./build.sh
```

The app has no third-party dependencies. A small async client speaks newline-delimited JSON-RPC to
`codex app-server --stdio`, while AppKit consumes a deterministic usage model. The response adapter tolerates
additive fields, prioritizes Codex bucket metadata, identifies supported windows by duration, and fails closed on
ambiguous, stale, or out-of-range values.

Provider churn is intentionally localized: session mechanics live in `CodexClient`, wire decoding and source
selection live in `CodexResponseParser`, and refresh retention lives in `RefreshFailurePolicy`. A transient launch,
connection, timeout, or schema failure keeps an unexpired report visible as explicitly stale. A missing executable or
account error clears the reading.

For local integrations, run the built executable with `--snapshot`. Output is stable and line-oriented: `limit_0` is
weekly usage and `limit_1` is five-hour usage. An unavailable window is omitted without renumbering the other one.

## Troubleshooting

- **"Codex is not installed"**: the app checks inside the ChatGPT desktop app, the Homebrew locations, and every
  absolute `PATH` entry. Install ChatGPT or the Codex CLI, then press Refresh.
- **"Sign in required" or another account error**: sign in to ChatGPT or run `codex login` in a terminal, then
  press Refresh.
- **The gauge shows `!`**: hover over the menu-bar item for the exact diagnostic. Run
  `"build/Codex Usage Micro.app/Contents/MacOS/CodexUsageMicro" --snapshot` for a direct provider check.

## Uninstall

Quit the app from its popover, then delete `build/Codex Usage Micro.app` or wherever you copied it. The app writes no
preferences, caches, login items, or other support files.

## Privacy and security

The app launches the locally installed Codex executable directly and reads only the account rate-limit response. It
does not accept network connections, persist account data, invoke a shell, or send telemetry of its own. JSON-RPC
responses must match the active request, output and diagnostics are bounded and sanitized, and stalled sessions are
terminated under a 12-second deadline. Codex inherits the user's existing local configuration and authentication.

## License

[MIT](LICENSE)

Codex Usage Micro is an unofficial utility and is not affiliated with OpenAI.
