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

## nens=500 rep1 results (runs 28594449255 / 28594450895, completed 2026-07-02 ~15:10 UTC)

maxD vs published (lower better):
| method | baseline/fresh-nens500 | exp/cr-pin-nens500 | delta (pin) |
|---|---|---|---|
| SCC | 0.116 | 0.162 | +0.046 |
| DCC | 0.186 | 0.166 | -0.020 |
| GAM | 0.154 | 0.156 | +0.002 |
| CPS | 0.312 | 0.277 | -0.035 |
| PaiCo | 0.116 | 0.159 | +0.043 |

**MIXED.** Decision rule not met on rep1: PaiCo (and SCC) regressed ~+0.045; CPS/DCC
gains held direction but attenuated vs nens=100. SCC flipped sign vs nens=100 (was a
win, now a loss), so these deltas may still be noise. CPS is the only consistent
signal across nens=100 and nens=500 (pin always improves it).

## IN FLIGHT (dispatched 2026-07-02 ~15:14 UTC) — replicate pair to pin the
## nens=500 noise floor. Runs 28600938435 (baseline) / 28600940099 (cr-pin).

Same branches re-dispatched (rep2). Rep1 CSVs remain in each branch's git history
(combine commits results per run). When both complete, score again and compare
rep2-vs-rep1 within each branch → empirical nens=500 noise floor. Then judge the
pin deltas above against that floor.

Decision rule (updated): promote the pin only if its CPS gain exceeds the empirical
noise floor AND the SCC/PaiCo regressions do NOT (i.e. they're noise). If SCC/PaiCo
regressions are real, do not promote globally; consider a CPS-only pin instead.
Dockerfile change already staged on `exp/cr-pin-1e3e0f2e`
(search for `remotes::install_github` in `Dockerfile` on that branch).

## Fresh-session relaunch instructions

If the SSH session dropped and you need to restart Claude Code from scratch:
1. Open Claude Code in `/Users/nicholas/GitHub/presto-Temp12k_Composites-trial`
2. Say: "Read reproduction/ci/HANDOFF.md and continue the fidelity plan."
   Claude Code will load memories automatically and resume from this file.
3. First thing to do: run the status check above, then score if complete, or wait.
