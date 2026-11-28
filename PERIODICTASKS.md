# Periodic Tasks

Maintenance notes, fork divergence summary, and recurring upstream sync checklist for this `libghostty-spm` fork.

## Fork Changes & Rationale

This repository tracks `Lakr233/libghostty-spm` (`upstream/main`) with a small rebaseable commit stack on top. GitHub Actions is disabled in repository settings so `.github/workflows/` remains untouched with zero diff against upstream.

- **Ghostty pin & local build/test scripts (`Ghostty.ref`, `Script/build.sh`, `Script/test.sh`)**: Pin `Ghostty.ref` to a tagged `vt-*` release (`vt-1.0.2`, compatible with local Zig `0.17.0`) instead of tracking arbitrary `main` commits; reset/clean `References/ghostty-upstream` before `--ref` checkout in `Script/build.sh` so previously applied patches never block a rebuild; make `Script/test.sh` check available XCFramework slices so macOS-only local builds (`--platforms macos`) don't fail on unbuilt iOS/visionOS/Catalyst destinations.
- **OSC 7501 Program Status (`Patches/ghostty/0090-program-status.patch`, `TerminalProgramStatus.swift`, callback hooks, tests)**: Ghostty's `libghostty-vt` parses OSC 7501, but the `libghostty` app runtime (`src/termio/stream_handler.zig`, `include/ghostty.h`) still ignores `.program_status`. Patch `0090` (high-numbered to avoid colliding with upstream patches) forwards OSC 7501 reports through `GHOSTTY_ACTION_PROGRAM_STATUS` and answers the support query; Swift exposes them via `TerminalSurfaceProgramStatusDelegate` / `TerminalSurfaceProgramStatusDetailsDelegate`.
- **Themes (`Script/generate-themes.sh`, `Sources/GhosttyTheme/Themes/`)**: Upstream ships 485 themes from `iTerm2-Color-Schemes`. Added local archive support to `Script/generate-themes.sh` and synced 907 themes from Ghostty's theme bundle.
- **AppKit `acceptsFirstResponder` isolation fix (`AppTerminalView+Lifecycle.swift`)**: Marks `acceptsFirstResponder` as `nonisolated` to avoid a Swift 6 main-actor isolation crash on macOS (still unfixed upstream).
- **Scoped text reading (`TerminalSurface+ReadText.swift`, `AppTerminalView+ReadText.swift`, `UITerminalView+ReadText.swift`, `TerminalViewState+ReadText.swift`, `TerminalReadTextTests.swift`)**: Exposes `TerminalTextScope` (`.viewport`, `.screen`, `.active`) and `readText(scope:)` wrapping `ghostty_surface_read_text` with `TOP_LEFT`/`BOTTOM_RIGHT` bounds so host apps can read terminal text without focusing or altering selection.

## Sync Upstream

- Last check: 2026-11-27
- Period: Monthly
- Last result: Rebased onto `Lakr233/libghostty-spm` (`2.2.2026112401`), pinned Ghostty `vt-1.0.2` (`573c4a21e023`), and released `2.2.2026112701`.

Steps:

1. Fetch `upstream` (`Lakr233/libghostty-spm`) and rebase `main` onto `upstream/main`.
2. Check for a newer Ghostty `vt-*` tag (or use `upstream`'s `Ghostty.ref`), reconcile `Patches/ghostty/0090-program-status.patch` and local commits, and drop anything upstream has incorporated (OSC 7501, themes, `acceptsFirstResponder`).
3. Rebuild the XCFramework (`./build.sh --platforms macos --ref <sha> --download-url ...`), verify tests and licenses, push `main`, and publish the storage and package releases.

## Sync Ghostty terminal themes

Run from the `libghostty-spm` repository root.

**Period:** Monthly

**Last sync:** 2026-11-15 — `libghostty-spm` `1.4.4`, with 907 themes from
Ghostty's `2026-11-09` pinned archive.

1. Resolve Ghostty's current pinned archive and download it:

   ```sh
   THEME_URL="$(rg -o 'https://deps\.files\.ghostty\.org/ghostty-themes-release-[^"]+' ../ghostty/build.zig.zon)"
   curl -fL "$THEME_URL" -o /tmp/ghostty-themes.tgz
   ```

2. Regenerate the catalog from that archive:

   ```sh
   ./Script/generate-themes.sh /tmp/ghostty-themes.tgz
   ```

3. Verify the generated count, update the theme count in `README.md` and
   `AGENTS.md`, then publish a new release and move downstream exact package
   pins (including Actor's) to it.
