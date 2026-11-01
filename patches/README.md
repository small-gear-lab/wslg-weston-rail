# patches

- `mr1667/1667.patch`: Weston merge request !1667 as downloaded, **unmodified**. It carries its authors' copyright and the
  license of the Weston files (MIT). Base commit: `9d841e39` (14.0.91+579).
- `local/*.patch`: our changes on top of it, applied in file-name order. They are changes to Weston files and stay under
  the license of those files, the Weston license (MIT), so that they can be sent upstream as they are. They are therefore
  **not** covered by the `MIT OR Apache-2.0` choice of the rest of this repository.

`scripts/fetch-sources.sh` applies both with `git am`. What each patch does: [../docs/patches.md](../docs/patches.md).
