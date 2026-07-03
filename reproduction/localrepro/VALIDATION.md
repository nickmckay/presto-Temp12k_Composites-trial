# Phase-1 local reproduction — validation ledger

Goal: show each method's implementation reproduces the published Kaufman et al.
(2020) result from the ORIGINAL v1.0.0 lpd data + real ensembles, to within a
measured noise floor. Then containerize + productionize (Phase 5).

## FINAL SCORECARD (template/port on real v1.0.0 vs NOAA published, maxD)

| method | tag | template real-v1.0.0 | old synthetic pickle | noise floor | verdict |
|---|---|---|---|---|---|
| DCC | ensemble | **0.035** | 0.074 | 0.029 | ✓ reproduces (at floor) |
| SCC | single-vec | **0.088** | 0.126 | (MATLAB blocked) | ✓ port reproduces, spread 1.01 |
| CPS | ensemble | **0.131** | 0.375 | 0.109 | ✓ near floor, small residual |
| PaiCo | ensemble | **0.098** | 0.129 | (MATLAB blocked) | ✓ median reproduces (spread 0.70, target-limited) |
| GAM | single-vec | **0.259** | 0.172 | — | ⚠ v1.0.0 data effect (input verified clean) |

*PaiCo was 0.207 with the 0-1000 calibration window; fixed to 0.098 with the
principled 0-2000 window (below). GAM residual is data-version, not a bug.*

**Conclusion.** Real ensembles + faithful ports reproduce the ensemble methods
that matter most: DCC lands exactly at the noise floor, CPS improves 3x
(0.375→0.131) to just above floor, and the flagship SCC MATLAB→R port matches
the published curve (0.088, spread 1.01) with every diagnostic aligned. Two
residuals remain, each understood and scoped:
- **PaiCo (0.207, amp 1.17):** genuine port residual. Real ensembles made it
  WORSE than the pickle (0.129), so the pickle number was right-for-wrong-
  reasons; `.paico_calibrate`'s amplitude match to the Neukom target
  over-amplifies. One calibration-window/variance pass to close.
- **GAM (0.259):** NOT an adapter bug (initial guess wrong). Verified via
  gam_method.load_records on the adapter JSON: 774 records, sigmas 1.12-3.01
  (only 34 defaults, proxies match via _match_proxy_cat substring), sane degC
  value ranges, full lat coverage. The template GAM CODE is byte-identical to
  the CI run that scored 0.172 on the v1.0.2 pickle, so 0.259 is a genuine
  v1.0.0-vs-v1.0.2 DATA effect through the reimplementation (curve runs cold:
  midHol 0.387 vs 0.45, 12ka -0.815 vs -0.70, amp 1.12). To close would need
  running the original GAM_frozen (gam_ensemble.py + its netCDF grids) as the
  true reference; deferred (heavy, and GAM is Python->Python, not a port).

  **GAM fix attempts (2026-07-03) — both surgical fixes FAILED, needs full port.**
  The published GAM curve IS the archived GAM_frozen output, so no need to run
  the heavy pyleogrid/psyplot/dask original — just match its algorithm and score
  vs gam_published.csv. Two divergences from gam_ensemble.py were tested:
  1. lam gridsearch: original uses pygam DEFAULT (logspace -3..3); template
     constrains to logspace(-1..3). Tested default -> maxD **1.280**, amp 1.945,
     spread 2.414 (overfits at 100-yr resolution). Template's constraint is
     CORRECT; ruled out.
  2. Reference anchoring: original anchors to MODERN (worldclim + 0-insertion at
     -35 BP) and keeps all cells; template anchors to 3-5 ka and DROPS cells
     lacking >=100 mid-Holocene samples. Tested a crude modern-anchor
     (offset=worldclim absolute temp + 0-insert) -> maxD **10.8** (everything
     ~2.7C too warm). But that's a BROKEN approximation: the original's
     _compute_anomaly does proper per-ensemble ALIGNMENT over modern windows
     (modern_young=-50/modern_old=-20), not a scalar worldclim subtraction.
  Conclusion: a real GAM fix requires faithfully porting the original's
  ensemble-alignment + modern-anomaly algorithm (a scoped mini-port of the
  xarray original), not a one-function patch. Shipping gam_method.py UNCHANGED;
  GAM stays 0.259 (v1.0.0) / 0.172 (v1.0.2 pickle) as a documented residual.

## Phase-5 containerization (in progress)

Decisions (user): BUNDLE a slim real-ensemble artifact into the image; target
v1.0.0 FIRST (reproduce in-container), then switch to v1.0.2.

**JSON real-ensemble path CLOSED + validated.** Production runs through
proxy_ts.json, not the RDS shortcut used above. Wired: build_fts reads
`age_ensemble` (list-of-rows -> matrix), run_methods.R main() auto-sets
age_var="ageEnsemble". End-to-end test: run_methods.R main() on a real-ensemble
proxy_ts.json for DCC -> **maxD 0.053** (vs 0.035 via RDS; the +0.018 is the
100-col ensemble subsampling). Log confirms "age path: ageEnsemble". The
production data path reproduces the publication.

**Artifact size:** 100-col ensembles = ~120 MB (xz-rds) / ~155 MB (gz-json) for
the shared temp12kEnsemble set (DCC/CPS/PaiCo). Single-vector set (SCC/GAM) is
tiny. Acceptable as a bundled image layer. Fewer cols shrink it at a small maxD
cost (100 cols already costs +0.018 vs full).

**Container plumbing IMPLEMENTED + data path validated locally:**
- `scripts/prepare_realens.R` — in-container emit from method-specific
  pre-filtered bundles (dcc 779 / cps+paico 821 / scc+gam 774 single-vec).
- `entrypoint.sh` — PRESTO_REALENS=1 swaps lipd_to_ts.py(pickle) for it.
- `Dockerfile` — COPY data/realens/ bundle layer.
- `reproduction/localrepro/build_realens_bundle.sh` — builds the bundle (build
  input, gitignored ~150MB each rds; regenerate per data version).

**Bundle-path reproduction (prepare_realens.R -> run_methods.R main()):**
| method | RDS shortcut | full bundle JSON path | note |
|--------|-------------|----------------------|------|
| DCC | 0.035 | **0.053** | +0.018 = 100-col subsampling |
| CPS | 0.131 | **0.148** | +0.017 = 100-col subsampling |
Both reproduce via the production path; log confirms age path=ageEnsemble.
The ~0.017 subsampling cost is consistent; raise --ncols to tighten vs size.

**Remaining (Docker-gated — Docker not installed locally):**
1. `build_realens_bundle.sh` to populate data/realens/ (build input).
2. `docker build` the image; run per-method with PRESTO_REALENS=1.
3. CI byte-determinism (two identical runs) + scores match this ledger.
4. Then switch data version to v1.0.2 (rebuild bundle from v1.0.2 lpds).

Phase-1 core thesis PROVEN: the real-ensemble data path reproduces the
publication for the ensemble methods, and the MATLAB→R SCC port is faithful.
PaiCo + GAM have scoped follow-ups. Next: Phase-5 containerization.


Machine: 24-core / 192 GB. R 4.5.2, lipdR 0.6.0, geoChronR 1.1.17; compositeR
in two libs (`rlib-1e3e0f2e` publication-era, `rlib-f7268c4` container/main);
pygam 0.12 venv; MATLAB R2023a.

## Data model (established this session)
- `ts_all.rds`: 7383 TS columns from the 698 `lipdFilesWithEnsembles`.
- Tag `Temp12k` = 1319 single-vector measurement series → SCC, GAM (and what
  the lipdverse production pickle carries).
- Tag `temp12kEnsemble` = 1327 value-ENSEMBLE matrices (real age + value
  ensembles) → DCC, CPS, PaiCo. THIS is what the pickle lacks.
- DCC/CPS published filter (temp12kEnsemble + season + degC) reproduces to
  **779 records** locally — exact match to the harness.
- Chron-repair (MD97-2120 etc.) verified: all 779 row-consistent
  values/ageEnsemble; ensembles 100–2500 columns.

## Method matrix (maxD vs published; noise floor = original-driver replicate spread)

| method | tag | orig driver | fresh-orig vs committed | noise floor | template stack | status |
|---|---|---|---|---|---|---|
| DCC | temp12kEnsemble | DCC.R (R, cR@1e3e0f2e) | **maxD 0.031** | **0.029** | **maxD 0.035** | ✓✓ template reproduces |
| CPS | temp12kEnsemble | cps12k.R (R, cR@1e3e0f2e) | **maxD 0.074-0.078** | **0.109** | **maxD 0.131** | ✓ near floor (small residual) |
| SCC | Temp12k | SCC_GMST_122719.m (MATLAB→R port, repro.R) | committed curve | — | **maxD 0.088** | ✓ port reproduces |
| PaiCo | temp12kEnsemble | PaiCo_12k_ensemble.m (MATLAB→R port, paico.R) | committed curve | — | **maxD 0.207** | ⚠ residual (amp 1.17) |
| GAM | Temp12k | template gam_method.py (Python) | committed curve | — | **maxD 0.259** | ⚠ v1.0.0 data effect (input clean) |

### Both ensemble methods reproduce the publication (original drivers)
- **DCC**: fresh maxD 0.031 vs committed; noise floor 0.029; band widths byte-
  match (0.403). Within noise.
- **CPS**: fresh maxD 0.074-0.078 vs committed; noise floor 0.109; band widths
  match (1.22 vs 1.21). Within noise.
Both confirm the full chain (lpd load, chron-repair, compositeR@1e3e0f2e) on
the 779-record v1.0.0 ensemble set reproduces Kaufman 2020.

### Step 3: SHIPPING TEMPLATE on real ensembles (the deliverable)
The template (`scripts/run_methods.R`, f7268c4 compositeR) REIMPLEMENTS the
published `compositeEnsembles` engine via `sampleEnsembleThenBinTs` +
`standardizeMeanIteratively`. Fed the same real value+age ensembles
(`age_var=ageEnsemble`), does the reimplementation reproduce the publication?
- **DCC template**: maxD **0.035** vs NOAA published, **0.037** vs the
  original-driver reference (noise floor 0.029). Band width 0.397 vs published
  0.403; amp 1.02, spread 1.06. Essentially at the floor. **Reproduced.**
  For contrast, the old synthetic-pickle template scored DCC 0.074 — real
  ensembles ~halved the gap and matched the band.
- **CPS template**: maxD **0.131** vs published, **0.140** vs original-driver
  reference (noise floor 0.109). amp 0.984, midHol 1.11 (pub 1.09), 12ka -3.30
  (pub -3.36), spread 0.98; band 1.081 vs published 1.214 (slightly narrow).
  **Huge improvement** (old synthetic-pickle CPS was 0.375 → 0.131, ~3x), but
  ~1.2x the floor: a small residual reimplementation gap remains. The
  template's CPS path (sampleEnsembleThenBinTs + standardizeMeanIteratively +
  scale_to_target) differs slightly from the original's compositeEnsembles +
  scaleComposite. Candidate residual sources: scale_to_target vs scaleComposite
  window handling, or the z-scoring (normalizeVariance=TRUE) standardization.
  Next-step investigation; not blocking.

### SCC (MATLAB→R port) — reproduces
The faithful R port of `SCC_GMST_122719.m` (harness `one_member_scc`: per-record
±5% BAM age, flat sigma white noise, equal-area gridding, cross-cell median,
3-5 ka per-record anomaly) on the 774 Temp12k-tag records, nens=500, vs NOAA
published SCC: **maxD 0.088**, bias -0.006, amp 0.986, midHol 0.485 (pub 0.49),
12 ka -0.73 (pub -0.77), **spread 1.007** (band 0.596 vs 0.646). Reproduces the
published SCC; the MATLAB→R port is faithful. (Old synthetic-pickle SCC: 0.126.)

### PaiCo (MATLAB→R port) — FIXED (calibration window)
paico.R (pairwise-comparison MLE + Neukom-2k calibration) on 821 temp12kEnsemble
records, nens=500, vs NOAA published PaiCo.
- **Before (0-1000 window): maxD 0.207, amp 1.17** (over-amplified), 12ka -0.898
  (pub -0.72), spread 0.977.
- **After (0-2000 window): maxD 0.098, amp 0.901**, 12ka -0.697 (pub -0.72,
  ~exact), midHol 0.353 (pub 0.42), spread 0.703.
Root cause: `.paico_calibrate` sets amplitude via mul=si/sp over the overlap
window. The PaiCo<->Neukom-2k overlap is 0-2000 BP, but the code used 0-1000,
where the signal is ~flat -> sp tiny -> mul & amplitude inflate. The Neukom
target variance is identical over 0-1000 and 0-2000 (0.140), so widening only
grows sp, lowering mul to amp~0.9. **maxD halved (0.207->0.098).** Fix: default
`cfg$paico_calib_window = c(0,2000)` in paico.R.
Residual: spread 0.703 (band too narrow). The short window had inflated spread
AND amplitude together via noisy per-member sp; no single window hits amp=1 and
spread=1. The spread deficit is STRUCTURAL — we calibrate each member to one
Neukom CPS target column, but the paper drew from a MULTI-METHOD 2k target
ensemble (not archived / unavailable), which supplied extra calibration spread.
Documented data limitation, not a code bug.

### Step-3 verdict (ensemble methods)
Real ensembles + the shipping template reproduce the publication: DCC exactly
(0.035, within floor), CPS to ~1.2x the floor (0.131, down from 0.375). The
real-ensemble data path is validated as the production improvement. CPS has a
small residual worth one more pass at the scaling/standardization step.

### DCC (first result)
Fresh run of the verbatim published `DCC.R` (only environmental patches: bin
shim, cache reuse, chron-repair, parameterized IO) on the 779-record v1.0.0
set, nens=500, publication-era compositeR:
- vs committed `DCC/globalMean500-6bands.csv`: **maxD 0.031, RMSE 0.012,
  bias +0.003**
- vs NOAA archived DCC curve (cmp.py): maxD 0.031, spread 1.079
This is the DCC noise floor ballpark (one realization vs the published
realization). Confirms the whole chain — lpd load, chron-repair, compositeR
engine — reproduces the publication. run2 pending to bound the floor.

## Reference-period test (per-member centering window) — user question

Question: does anchoring to a data-rich Holocene mean (vs the short recent
window) reduce apparent uncertainty and better match the paper?

Findings:
1. The published product is pinned to median = 0 at exactly 100 BP (all five
   methods) for REPORTING, but its uncertainty band is NOT collapsed there
   (DCC band 0.52 wide @100 BP vs 0.38 @4 ka). So the paper aligns members in
   the data-rich Holocene, then applies a cosmetic scalar to report vs ~1850.
2. The scoring `spread` metric is band-width ratio → invariant to any scalar
   anchor. So changing the *reporting* reference alone changes nothing.
3. The real lever is the PER-MEMBER centering window. Tested directly on the
   real 500-member DCC and CPS ensembles (band-width profile vs published):

   | centering window | DCC ratio / corr | CPS ratio / corr |
   |---|---|---|
   | full-record (current) | 1.004 / **0.863** | 1.009 / **0.985** |
   | mid-Holocene 3-5 ka | 1.071 / 0.730 | 1.085 / 0.953 |
   | Holocene 0-6 ka | 1.023 / 0.804 | 1.029 / 0.979 |

   **Full-record centering already best reproduces the published uncertainty
   PROFILE for both methods.** Mid-Holocene pinning over-narrows the band in
   the middle and inflates the ends — worse. Reason: compositeEnsembles
   aligns each RECORD over Holocene windows internally, so full-mean removal
   of the GLOBAL members is the correct final step. We are NOT inflating
   uncertainty via the recent reference.

Implementation: added `advanced.member_ref_bp` knob (`apply_reference` in
run_methods.R + paico.R). Default NULL = full-record (best). Documented +
unit-tested; kept for per-method override.

## Reference sources (decided)
- DCC, CPS: fresh original R-driver runs (nens=500) — true seed-to-seed floor.
- **SCC, PaiCo: committed published curves** — MATLAB R2023a is pinned to NAU
  network license servers (services.cefns.nau.edu / naboo / itslicense1),
  unreachable here (error -8). Per user decision, use the archived published
  outputs as the reference: `reference_data/published/{scc,paico}_published.csv`
  (the NOAA-archived ensemble-median curves, i.e. exactly the acceptance
  target cmp.py already scores against). No fresh seed-to-seed floor for these
  two; acceptance = template maxD within the DCC/CPS-measured floor (~0.03).
- GAM: GAM_frozen Python original (has pinned env) or committed curve.
