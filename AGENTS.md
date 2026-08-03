# PIXCAPTURE iOS External Review Rules

This repository is a self-contained public review snapshot. Do not expect or
follow files outside this repository.

Before reviewing code, read only:

1. `README.md`
2. `EXTERNAL_REVIEW_SCOPE.md`
3. `docs-mobile/EXTERNAL_REVIEW_CONTRACT.md`
4. `docs-mobile/RELEASE_3_9_VERIFICATION_20260803.md`

Review the implementation under `ios/`, especially camera orientation and
level mapping, local-data safety, authentication boundaries, WebRTC failure
handling, upload retry semantics, and the automated tests.

The repository is an isolated copy. Findings should be reported to the owner;
do not assume that changing this snapshot changes the private production
repository.
