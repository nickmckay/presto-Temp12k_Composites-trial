# Local Phase-1 reproduction — session handoff (START HERE)

Authoritative state for the LOCAL real-ensemble reproduction work. Supersedes
the CI-era `reproduction/ci/HANDOFF.md` (that phase's determinism/CPS-lever work
is DONE and merged to main; see it only for history). Full ledger:
`reproduction/localrepro/VALIDATION.md`. Memory: `project_phase1-localrepro.md`.

Branch: **`local/phase1-real-ensembles`** (all work pushed; not merged to main).

## What this phase proved
Feed the SHIPPING template real per-record age+value ensembles (from the 698
v1.0.0 lpd files) instead of the lipdverse pickle's synthetic single vectors,
and it reproduces the published Kaufman 2020 curves. Scorecard (template/port on
real v1.0.0 vs NOAA published, maxD; noise floors DCC 0.029 / CPS 0.109):

| method | maxD | status |
|--------|------|--------|
| DCC   | 0.035 | ✓ at floor |
| SCC   | 0.088 | ✓ MATLAB→R port reproduces (spread 1.01) |
| PaiCo | 0.098 | ✓ MATLAB→R port; FIXED (was 0.207, calib-window bug) |
| CPS   | 0.131 | ✓ near floor |
| GAM   | 0.259 | ⚠ residual — needs a port (see below) |

Old synthetic-pickle scores for contrast: DCC 0.074, SCC 0.126, CPS 0.375,
PaiCo 0.129, GAM 0.172.

## Environment (this machine — 24 core)
- Temp12k clone: `~/GitHub/Temperature12k` (698 lpds in
  `ScientificDataAnalysis/lipdFilesWithEnsembles`; original drivers DCC.R,
  cps12k.R, SCC_GMST_122719.m, PaiCo/*, GAM_frozen/scripts/gam_ensemble.py).
- compositeR two libs: `reproduction/localrepro/rlib-1e3e0f2e` (publication),
  `rlib-f7268c4` (container/main). Select via `R_LIBS_USER=...`.
- pygam venv: `reproduction/localrepro/venv`.
- Caches (gitignored, rebuild if missing): `reproduction/localrepro/cache/`
  — `ts_all.rds` (7383 TS cols), slim caches `fts_{dcc,cps,scc}.rds`,
  `proxy_ts_gam.json`. Rebuild: `bash reproduction/localrepro/run_repro.sh cache`
  then `Rscript reproduction/localrepro/build_slim.R --method cps ...`.
- **MATLAB R2023a is license-BLOCKED** (NAU network servers, error -8) → SCC/
  PaiCo use the committed NOAA published curves as reference, not fresh reruns.

## Key scripts (reproduction/localrepro/)
- `run_repro.sh cache|harness <m>|score` — driver.
- `originals/orig_{dcc,cps}.R` — verbatim published R drivers (patched only for
  env: bin shim, cache reuse, chron-repair, IO). Reproduce refs within noise.
- `run_template_realens.R` — SHIPPING run_method on the slim cache (RDS path).
- `emit_realens_json.R` / `prepare_realens.R` — emit real-ensemble proxy_ts.json.
- `build_realens_bundle.sh` — builds the container bundle (data/realens/).
- `export_ts_mat.R` + `ndjson_to_tsmat.py` + `run_scc.m` — MATLAB SCC path (blocked).

## Shipping-code changes made this phase (on the branch)
- `scripts/run_methods.R`: `build_fts` reads `age_ensemble`; `run_method` takes
  `cfg$age_var` and main() auto-sets it to "ageEnsemble" when real ensembles are
  present. `apply_reference` gains `member_ref_bp` (default full-record = best).
- `scripts/paico.R`: `cfg$paico_calib_window` default **c(0,2000)** — the PaiCo
  fix (0.207→0.098).
- `entrypoint.sh`: `PRESTO_REALENS=1` mode (uses prepare_realens.R vs pickle).
- `Dockerfile`: COPY `data/realens/` bundle layer.
- `scripts/gam_method.py`: UNCHANGED (GAM fixes failed, see below).

## NEXT TASKS (in priority order)

### 1. GAM fix — port the original anomaly/alignment algorithm (scoped mini-port)
GAM is the one method still off (0.259). Cheap fixes were tested and FAILED:
- default lam gridsearch → maxD 1.280 (overfits); template's lam constraint is
  CORRECT, ruled out.
- crude modern-anchoring (subtract worldclim abs temp + 0-insert at -35 BP) →
  maxD 10.8; a BROKEN approximation.
The real difference: `gam_ensemble.py::_compute_anomaly` anchors to MODERN via
per-ensemble ALIGNMENT over modern windows (modern_young=-50, modern_old=-20;
worldclim 1970-2000) + 0-insertion at -35 BP, and KEEPS all cells; our
`gam_method.py` anchors to 3-5 ka and DROPS cells lacking ≥100 mid-Holocene
samples (fit_cell L371-372). Fix = faithfully port that alignment/anomaly logic.
Reference to match = `reference_data/published/gam_published.csv` (IS the
archived GAM_frozen output, so no need to run the pyleogrid/psyplot/dask
original). Test cmd (template GAM on v1.0.0):
```
reproduction/localrepro/venv/bin/python scripts/gam_method.py \
  --ts reproduction/localrepro/cache/proxy_ts_gam.json --config config/user_config.yml \
  --grid reference_data/equal_area_grid_centers.csv \
  --sigma-table reference_data/proxy_uncertainties.csv \
  --modern-grid reference_data/worldclim_modern_1deg.csv --out-csv /tmp/gam.csv
python3 reproduction/ci/cmp.py --method gam --csv /tmp/gam.csv
```
Scratch experiment copies (this session, in scratchpad, not committed):
gam_ensemble.py (original), gam_default_lam.py, gam_modern.py (broken).

### 2. Phase-5 containerization — Docker-gated (Docker NOT installed here)
Plumbing done + data path validated locally (DCC 0.053, CPS 0.148 via the
bundle→proxy_ts.json→run_methods path; +0.017 vs RDS = 100-col subsampling).
Remaining: `bash reproduction/localrepro/build_realens_bundle.sh` → populate
`data/realens/`; `docker build`; run per-method `PRESTO_REALENS=1`; CI
byte-determinism (two identical runs) + scores match the ledger; THEN rebuild
the bundle from v1.0.2 lpds for production (pickle path stays fallback).

### 3. Optional CPS residual (0.131, small) + PaiCo spread (0.70, target-limited)
Both understood and documented; low priority.

## Merge decision
Branch is ready for review. It changes shipping scripts (guarded/backward-
compatible defaults) + adds the container real-ensemble path + all localrepro
tooling. Nothing merged to main yet.
