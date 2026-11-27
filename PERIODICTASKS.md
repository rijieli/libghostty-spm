## Sync Upstream

- Last check: 2026-11-27
- Period: Monthly
- Last result: Rebased onto `Lakr233/libghostty-spm` (`2.2.2026112401`), pinned Ghostty `vt-1.0.2` (`573c4a21e023`), and released `2.2.2026112701`.

Steps:

1. Fetch `upstream` (`Lakr233/libghostty-spm`) and rebase `main` onto `upstream/main`.
2. Check for a newer Ghostty `vt-*` tag (or use `upstream`'s `Ghostty.ref`), reconcile `Patches/ghostty/0090-program-status.patch` and local commits, and drop anything upstream has incorporated (OSC 7501, themes, `acceptsFirstResponder`).
3. Rebuild the XCFramework (`./build.sh --platforms macos --ref <sha> --download-url ...`), verify tests and licenses, push `main`, and publish the storage and package releases.
