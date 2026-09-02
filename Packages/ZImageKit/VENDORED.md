# Vendored: zimage.swift

- **Upstream:** https://github.com/mzbac/zimage.swift
- **Vendored at:** `970f83e477028e81fc19fc7035228ced89dc1ffd` (`main`, 2025-12-20).
  Tag `0.1.2` predates the resident-pipeline API (`loadModel`, `generateToMemory`,
  progress callbacks), so `main` was used.
- **License:** MIT, per upstream `README.md` "License" section. The upstream
  repository has **no LICENSE file**; the text in `LICENSE` here is the standard
  MIT text with the upstream author as copyright holder.
- **Included:** `Sources/ZImage/**` (49 files, directory tree preserved verbatim).
- **Excluded:** `Sources/ZImageCLI`, `Tests/**`, `examples/**`, `images/**`.

## Manifest changes (Package.swift)

- tools-version 5.9 → 6.0; platforms macOS 14 → 15; iOS dropped.
- mlx-swift `.upToNextMinor(from: "0.29.1")` → `exact: "0.31.3"`.
- Added `swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]`
  on the `ZImage` target. The upcoming feature makes the pipeline's async methods run on the
  caller's executor, so Zephra's inference actor keeps MLX work on its own serial queue.
- Dropped CLI and test targets (Zephra has its own `ZephraBench` tool).

## Re-sync procedure

```sh
git clone https://github.com/mzbac/zimage.swift /tmp/zimage-src
git -C /tmp/zimage-src diff 970f83e4..<new-sha> -- Sources/ZImage > /tmp/zimage.diff
# hand-apply against Packages/ZImageKit/Sources/ZImage, re-apply the patches below
```

## Local patches

Every local edit carries a `// ZEPHRA-PATCH: <reason>` comment and a line here.

- `Pipeline/ZImagePipeline.swift`, `Pipeline/ZImageControlPipeline.swift`: `RandomStateOrKey?` seed key
  typed as `MLXArray?` (mlx-swift 0.31 rejects the existential in the generic `key:` parameter). 3 sites.
- Same files: CFG blend `guidanceScale * (positive - negative)` wraps the scalar in `MLXArray(...)`
  because Swift 6.3 resolved the `*` to an unrelated overload. 3 sites. No behaviour change.

## Known upstream behaviour (not patched)

- Loading `mzbac/Z-Image-Turbo-8bit` logs a failure to apply the
  `all_final_layer` / `adaLN_modulation` submodule weights and then reports success.
  Output images are correct, so the branch appears unused for this model. Treat as noise
  until proven otherwise.
- Peak memory during weight loading is ~27 GB on an M4 Max versus ~13 GB resident
  afterwards: shards are read fully before being applied. Candidate for a ZEPHRA-PATCH
  that streams shard by shard.
