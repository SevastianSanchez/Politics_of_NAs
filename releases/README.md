# Releases

The permanent, citable copy of every version is on **Zenodo**. Concept DOI
[10.5281/zenodo.23997606](https://doi.org/10.5281/zenodo.23997606) always
resolves to the newest version. Cite the version DOI of the release you used.

## How releases are packaged

**From v1.4.0**, each release on Zenodo contains:

- **the VSI bundle**: the score files, per-goal diagnostics, a data dictionary
  and the release notes, for anyone who wants the data; and
- **a zip of the full repository at that version's git tag**, for anyone who
  wants to check or rerun the work.

No folder is added here for v1.4.0 or later: the git tag marks the exact code
and data, and Zenodo holds the deposited files.

**Earlier releases were packaged differently.** The folders below are frozen
copies of what was deposited for each version: a hand-picked set of files, not
the full repository. Their scripts expect the repository layout of that time,
so they do not run on their own. **The full code and data for any version** is
available from its git tag: open the tag on GitHub and download
"Source code (zip)".

| Version | Published as | Zenodo version DOI | Git tag | Folder here |
|---|---|---|---|---|
| 1.0.0 | The World on Record | [10.5281/zenodo.23997607](https://doi.org/10.5281/zenodo.23997607) | `v1.0.0` | none (Zenodo holds a zip of the full repository) |
| 1.1.0 | — | none: never deposited | none | `v1.1.0/` (see its `SUPERSEDED.md`) |
| 1.2.0 | The World on Record | [10.5281/zenodo.24091914](https://doi.org/10.5281/zenodo.24091914) | `v1.2.0` | `v1.2.0/` |
| 1.2.1 | The World on Record | [10.5281/zenodo.24094834](https://doi.org/10.5281/zenodo.24094834) | `v1.2.1` | `v1.2.1/` |
| 1.3.0 | Visible States | [10.5281/zenodo.24100866](https://doi.org/10.5281/zenodo.24100866) | `v1.3.0` | `v1.3.0/` |

Files in these folders are never edited after release.
