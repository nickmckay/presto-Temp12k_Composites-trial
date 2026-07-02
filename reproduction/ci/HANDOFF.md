# Fidelity work — session handoff (for continuing on another machine)

Goal: improve the presto-Temp12k container's fidelity to Kaufman et al. (2020),
verified via **GitHub Actions CI** (the container + lipdverse pickle + methods run in
the cloud). No local Docker/R/pandas required to drive it.

## New-machine requirements (lightweight driver only)
- `git`; `gh` CLI **authenticated** (`gh auth login`; needs `repo`+`workflow` scopes on
  the fork `nickmckay/presto-Temp12k_Composites-trial`).
- `python3` + `numpy` (scoring only — NO Docker, R, or pandas needed here).
- Claude Code. Start a fresh session in the cloned repo; have it read this file + the
  project memory (see below).
- **One-time:** Actions must be enabled on the fork (Actions tab → "enable workflows").
  Already done on the current fork.

## How the loop works
1. Make a single-variable change on a branch off `main`; push to `origin`.
2. `bash reproduction/ci/dispatch_all.sh <branch>` — dispatches `reconstruct.yml`
   (archived payload Temp12k v1_0_2). CI runs 5 methods + `combine`, which **commits
   `results/methods/*.csv` back to the branch**.
3. `bash reproduction/ci/score_branch.sh <branch>` — fetches + scores each method's maxD/
   bias/spread. `cmp.py` reproduces the authoritative `comparison.json` EXACTLY.
   Each CI run ≈ 25-30 min; runs on different branches go in parallel.

## Current results (maxD vs published; lower better; nens=100 noise floor ≈ ±0.05)
| method | committed baseline (STALE) | fresh `main` | `exp/scc-median` | `exp/cr-pin-1e3e0f2e` |
|---|---|---|---|---|
| SCC | 0.225 | 0.144 | 0.184 | 0.127 |
| DCC | 0.200 | 0.163 | 0.139 | 0.085 |
| GAM | 0.167 | 0.165 | 0.168 | 0.169 |
| CPS | 0.656 | 0.422 | 0.370 | 0.276 |
| PaiCo | 0.115 | 0.140 | 0.096 | 0.167 |

### Conclusions
1. **Committed `comparison.json` is STALE** — fresh `main` is CPS 0.422 (not 0.656),
   better across the board (base image `lipdbase2` is a mutable tag / pickle drifted
   favorably). Regenerate the repo's headline baseline from a fresh `main` run.
2. **compositeR publication pin (1e3e0f2e) is a real win** vs fresh main: CPS −0.15,
   DCC −0.08; GAM flat (Python control) and PaiCo within noise (its core is the recent
   R port, uses compositeR only for binning). Confirm at nens=500, watch PaiCo.
3. **`exp/scc-median` is NOT a win** (SCC 0.144→0.184, within noise; gridMat.m absent so
   unverifiable). Drop it.
4. **CPS record-subset was a dead end** — template keeps 809 records vs harness 779
   (~30 apart), and the pickle has no `temp12kEnsemble` tag (uses `inCompilation="Temp12k"`).
   The CPS gap is the **age-ensemble + value-ensemble** axes, not subset. The template
   propagates NO age uncertainty (`ageVar="age"` single vector; README's "BAM ±5%" claim
   is false) — likely the real CPS/SCC lever.
5. **Noise floor ≈ ±0.05 at nens=100.** Small effects need nens=500 or replicates.

## Next steps (priority)
1. Regenerate the stale baseline (one fresh `main` run → update `comparison.json`).
2. nens=500 confirmation of the compositeR pin (`exp/cr-pin-1e3e0f2e`); if it holds and
   PaiCo doesn't regress, promote it (bake `remotes::install_github(...,ref="1e3e0f2e")`
   into the Dockerfile — already staged on that branch).
3. CPS/SCC: implement genuine age-uncertainty propagation (BAM fallback + real ensembles
   when present) instead of the single median-age vector.

## Branch map (all pushed to origin)
- `overnight/fidelity-plan` — housekeeping commits (sin-lat weights, dead-knob docs),
  audit refresh, `reproduction/audit/overnight_2026-07-01.md` write-up, these ci helpers.
- `exp/cps-t12kensemble` — FAILED (temp12kEnsemble tag absent); dead end.
- `exp/scc-median` — SCC rowMeans→median; not a win.
- `exp/cr-pin-1e3e0f2e` — compositeR publication pin; the promising one.
- `baseline/fresh` — no-op off main; the fresh control baseline.
Nothing merged to `main`.

## Project memory (copy or re-read)
Machine-local at `~/.claude/projects/-Users-nicholas-GitHub-presto-Temp12k-Composites-trial/memory/`
(`temp12k-fidelity-plan`, `-fidelity-status`, `-ground-truth-local`, `-dev-environment`).
Full plan: `~/.claude/plans/take-a-look-through-inherited-honey.md`. Everything actionable
is also summarized in this file, so a fresh session can proceed from here alone.

## IN FLIGHT (dispatched 2026-07-02 ~08:45 CDT) — collect these first
Two nens=500 confirmation runs of the compositeR pin are RUNNING in CI (~1-2 h):
- `baseline/fresh-nens500` — nens=500 control (unmodified main).
- `exp/cr-pin-nens500` — nens=500 + compositeR@1e3e0f2e pin.
When done: `bash reproduction/ci/score_branch.sh baseline/fresh-nens500` and
`... exp/cr-pin-nens500`. Expect the pin to hold its CPS/DCC gains with the nens=100
noise (±0.05) collapsed. If it holds and PaiCo doesn't regress → promote the pin
(bake into Dockerfile; already staged on the cr-pin branches).
Watch: `gh run list -R nickmckay/presto-Temp12k_Composites-trial --workflow=reconstruct.yml`
