# CLAUDE.md

Kero is a native macOS terminal workspace with projects, panes, a file tree, a git panel,
an editor, and a diff viewer. Existing SwiftUI code is legacy; AppKit is the UI foundation.

- [PRODUCT.md](PRODUCT.md) — who Kero is for; product and design calls follow from it.
- [CONTRIBUTING.md](CONTRIBUTING.md) — build, verify, and what a PR must say. Read before opening one.
- [RELEASING.md](RELEASING.md) — maintainer-only. Never bump the version in a PR.

## Verify

- Unit tests: `xcodebuild -project kero.xcodeproj -scheme kero -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test`
- Rust bridge: `cargo test --manifest-path Vendor/alacritty-bridge/Cargo.toml --locked`
- Then build, run the app, and exercise the change by hand — most of Kero is UI the tests do not cover.

## Conventions

- Match the file you're in. Comments explain *why* — keep them, add them.
- SwiftUI is legacy and must not be introduced or expanded. Build all new UI in AppKit;
  when materially changing an existing SwiftUI view, migrate the affected UI to AppKit.
  UI architecture must prioritize maximum runtime performance over implementation convenience.
- [CHANGELOG.md](CHANGELOG.md) is the product changelog for end users, not a
  development log. Describe only the final user-visible outcome intended to
  ship. Never add or revise release notes for incremental fixes, refactors,
  implementation details, or regressions introduced and resolved while a
  feature is still in progress on an unreleased branch.
