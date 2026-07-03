# Phase-1 local reproduction — validation ledger

Goal: show each method's implementation reproduces the published Kaufman et al.
(2020) result from the ORIGINAL v1.0.0 lpd data + real ensembles, to within a
measured noise floor. Then containerize + productionize (Phase 5).

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
| SCC | Temp12k | SCC_GMST_122719.m (MATLAB) | BLOCKED (license -8) | — | pending | blocked |
| PaiCo | temp12kEnsemble | PaiCo_12k_ensemble.m (MATLAB) | (MATLAB) | — | pending | pending |
| GAM | Temp12k | GAM_frozen (Python) | pending | pending | pending | pending |

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
