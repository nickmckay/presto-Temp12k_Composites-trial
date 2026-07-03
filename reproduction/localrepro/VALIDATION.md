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
| DCC | temp12kEnsemble | DCC.R (R, cR@1e3e0f2e) | **maxD 0.031** | (run2 pending) | pending | orig ✓ |
| CPS | temp12kEnsemble | cps12k.R | in flight | pending | pending | running |
| SCC | Temp12k | SCC_GMST_122719.m (MATLAB) | BLOCKED (license -8) | — | pending | blocked |
| PaiCo | temp12kEnsemble | PaiCo_12k_ensemble.m (MATLAB) | (MATLAB) | — | pending | pending |
| GAM | Temp12k | GAM_frozen (Python) | pending | pending | pending | pending |

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
