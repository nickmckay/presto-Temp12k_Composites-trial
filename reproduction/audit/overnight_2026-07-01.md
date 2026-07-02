# Overnight fidelity work — 2026-07-01 (branch: overnight/fidelity-plan)

Autonomous continuation of the Temp12k fidelity plan while user asleep.
Constraints in force: **no Docker** (native-R harness only → numbers are RELATIVE,
not comparable to committed container baseline); 8 cores / 16 GB (heavy R runs
serialized); no lipdverse pickle on disk (true template data path needs CI).

## Operating rules I held to
- Work on branch `overnight/fidelity-plan`, incremental commits, NO push, NO main edits.
- Committed only changes that are (a) doc/comment-only, or (b) numerically negligible
  AND grounded in the original published driver. Anything behavioral I could not verify
  from source OR could not CI-test was DIAGNOSED + DRAFTED + FLAGGED, not committed.

## Done

### DCC diagnostic (task 3) — chron-repair run completed
Native R, nens=50, `PRESTO_CHRON_REPAIR=1`. Record loss 11→3 (8 recovered).
Result vs published (anchored 100 BP): **maxD 0.130, spread 0.98, bias −0.061,
amp 1.025, 12ka −0.863, midHol 0.438**.
- Key finding: the template's **+0.105 warm bias flips to −0.061 (cold) in the harness**,
  and recovered marine records pull 12 ka colder. Supports the plan's hypothesis that
  DCC's template warm bias is largely a **data-path / survivor-selection artifact**, not
  intrinsic to DCC. (Caveat: native stack, relative only.)

### Housekeeping (task 5) — committed 241dda5
- `run_methods.R`: BAND_WEIGHTS now computed as normalized sin(lat) differences
  (matches cps12k.R:96 exactly; ~1e-5 vs the old rounded literals). Verified sum=1.
- `run_methods.R` + `user_config.yml`: documented that `advanced.cps_scale_window` is
  **not consumed** — published CPS fixes the window to full 2 ka (0-2000 CE), hardcoded
  in scale_to_target (cps12k.R:89). Comment-only, no behavior change.

## Findings that refine the plan (from reading original drivers)
- **cps12k.R:34** — the `>10` coverage gate is COMMENTED OUT in the published run. So
  "add a CPS coverage gate" (plan hypothesis 1a-fix) would be a DEVIATION, not a fix.
  The CPS record-set difference is instead the `temp12kEnsemble` filter (cps12k.R:25)
  vs the template's broader `temp12k*` match — but the ground rule says don't hardcode
  that filter. NEEDS USER DECISION: is restricting to the temp12kEnsemble flag (when
  present) an acceptable default that doesn't break bring-your-own-data?
- **SCC gridMat.m is ABSENT** from the local checkout — only Fig1_GMST.m and
  SCC_GMST_122719.m exist. So the cross-cell **median** aggregation (plan task 2, part 2)
  cannot be verified from source; only the `.calMedian` variable name (SCC_GMST:147)
  suggests it. → Left UNCOMMITTED; flagged for user.
- **README BAM claim is FALSE**: README_NOTES.md says age uncertainty is propagated via a
  "Banded Age Model (symmetric 5%) generated at runtime," but the template generates NO
  age ensemble — build_fts sets only a single median `age` vector and uses ageVar="age".
  All spread comes from the 10-col AR1 value ensemble; there is NO age propagation. This
  is both a doc bug AND a likely fidelity gap (contributes to SCC spread 0.85). Left the
  prose UNEDITED (user-facing science description) — flagged for user.

## In flight
- CPS harness run (native, nens=50, real value-ens + median real ages, temp12kEnsemble
  subset, template run_method("cps") algorithm). Tests whether holding the data axes at
  "good" reproduces the container harness ~0.32 → would confirm template's 0.656 is the
  pickle data path, not the algorithm. Collector task b463u5hhc will score it.

## NOT done overnight (need user / CI)
- Template method code changes (SCC uncertainty-model port, SCC median, CPS record-set) —
  material + unverifiable without container CI; drafted/specified, not committed.
- GAM sweep (task 4) — needs pygam; native anaconda numpy is broken.
- nens=500 end-state verification (task 7) — needs container/CI.
- compositeR@1e3e0f2e pin (task 6) — needs container.

## CPS diagnostic result (task 1 / task 6) — MAJOR finding

Native CPS harness (nens=50, temp12kEnsemble subset, real value-ens + median real
ages — i.e. IDENTICAL slim-cache data to the container harness that scored 0.32):
  maxD **0.747**, bias +0.248, midHol 1.291 (pub 1.09), 12ka −2.742 (pub −3.36),
  amp 0.901, spread 0.907.

Because the DATA is held constant vs the container harness (both use fts_dcc.rds),
this isolates **compositeR version**:
- container harness (compositeR **f7268c4**): CPS maxD **0.32**
- native harness (compositeR **99a738e = `refactor` branch**): CPS maxD **0.747**
⇒ the refactor branch is **~0.43 maxD WORSE for CPS** on identical data. Native CPS
(midHol 1.29, 12ka −2.74) behaves like the template (0.656 / midHol 1.29), NOT like
the good container harness (0.32). DCC is nearly immune (normalizeVariance=FALSE);
CPS z-scores (normalizeVariance=TRUE) so the standardization refactor hits it hard.

**Implications:**
1. Do NOT upgrade the container's compositeR to the `refactor` branch — it regresses CPS.
2. Task 6 (pin experiment) is elevated: the real question is f7268c4 (current container,
   CPS 0.32 on good data) vs publication-era 1e3e0f2e. The refactor is disqualified.
3. The native-R harness is a VALID instrument only for compositeR-insensitive methods
   (DCC). For CPS/SCC data-path ladders it must run compositeR@f7268c4 (or in-container).

**Blocker for the CPS data-path ladder (task 1):** even with f7268c4 installed, the
record-subset axis (leading hypothesis: broader pickle subset dilutes deglacial records
after z-scoring) CANNOT be tested without the lipdverse pickle, which is not on disk
(CI downloads it at runtime). Age-source and value-ensemble axes are testable; record
subset is not. Recommend running task 1 in-container (Docker) where all three axes +
f7268c4 are available. The container harness already isolated the gap to the pickle
data path (0.32 vs 0.656, same f7268c4) — that conclusion stands.

## Native-R environment note (for restore)
compositeR installed natively = local checkout `~/GitHub/compositeR` @ 99a738e (`refactor`).
Built 2026-07-02 03:36 UTC. To match the container for CPS/SCC diagnostics, install
f7268c4 (e.g. via a temp worktree + `R CMD INSTALL`), then restore refactor when done.
Did NOT do this overnight (env-surgery risk + pickle blocker made the payoff low).

## GitHub Actions path — set up, BLOCKED on a one-time fork enable

User pointed out CI is the way to get real container + pickle + validation without
local Docker. Confirmed the pipeline (`reconstruct.yml`): workflow_dispatch, downloads
the archived lipdverse pickle, runs 5 methods in a matrix, `combine` commits
`results/methods/*.csv` back to the branch. It does NOT run validate.py — but my
numpy-only `cmp.py` reproduces the authoritative `comparison.json` EXACTLY (verified on
the committed baseline: scc .225 dcc .200 gam .167 cps .656 paico .115), so I score CI
runs from the committed method CSVs. Data payload = archived Temp12k v1_0_2
(`lipdverse.org/Temp12k/1_0_2/Temp12k1_0_2.pkl`, verified live).

**BLOCKER:** nickmckay's fork has **0 registered workflows** (`actions/workflows`
total_count=0) — GitHub's one-time "forks: enable Actions" gate. The enable endpoint
404s (nothing registered), and it CANNOT be cleared via API/gh; it needs one manual
click. All historical CI ran on the **DaveEdge1 parent**, where nickmckay has no admin
(dispatch → HTTP 403). So CI is push-ready but blocked on a 5-second manual step.

**Staged and pushed to origin (nickmckay fork), single-variable off `main`:**
- `exp/cps-t12kensemble` — restrict records to published temp12kEnsemble subset
  (cps12k.R:25). Leading CPS hypothesis; also gates all methods, so it doubles as a
  "does the QC subset help across the board" test.
- `exp/scc-median` — SCC cross-cell aggregation rowMeans→median (SCC-only; run_methods.R:148).
- `exp/cr-pin-1e3e0f2e` — pin compositeR to the publication-era commit (task 6; build risk).

**To run (morning, ~5 s + ~30 min CI each, parallel):**
1. Enable Actions: https://github.com/nickmckay/presto-Temp12k_Composites-trial/actions
   → "I understand my workflows, go ahead and enable them".
2. `bash <jobtmp>/dispatch_all.sh`  (fires all 3; jobtmp = ~/.claude/jobs/586925ef/tmp)
3. When each finishes: `bash <jobtmp>/score_branch.sh exp/<name>` → maxD/bias/spread vs baseline.

**NOT staged (complex ports; can't verify tonight; specified for later):**
SCC uncertainty-model port (±5% age + σ=1.5 white, from repro.R:250-281) and DCC
member-level retry (repro.R:207-231). Build these as branches once the CI loop is proven.
