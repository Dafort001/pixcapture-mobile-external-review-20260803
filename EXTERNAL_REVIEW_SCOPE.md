# PIXCAPTURE iOS external review snapshot

This private repository is an isolated review copy. It is not connected to the production repository and cannot change the production source.

## Provenance

- Released-source commit: `5f2fa402479b688dd173df788a10a60cf0c4b48f`
- Released-source tree: `b7077af20b0c56d42c564e6db4047e32f3cd5bea`
- App version: `3.8`
- App Store build: `202607172137`
- Snapshot date: `2026-08-03`

All included files match that source commit. The review copy intentionally excludes:

- `ios/PIXCAPTURE/Vendor/opencv2.xcframework`: 327 MB third-party binary/header bundle used only by the hidden Panorama/ArUco implementation; preserved separately with SHA-256.
- `backend/`: legacy/non-iOS backend copy; not referenced by the Xcode project.
- `docs-mobile/`: historical handovers and duplicate export archives, not production app code.
- personal Xcode `xcuserdata`.

The external reviewer should focus on `ios/PIXCAPTURE`, the Xcode project, iOS tests, and the release scripts. Findings should be reported outside this repository until the owner explicitly requests a review branch.
