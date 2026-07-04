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
| GAM   | 0.155 | ✓ FIXED via real value ensembles + 0-insert (was 0.259) |

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
- `scripts/gam_method.py`: **CHANGED — GAM FIXED (2026-07-03), see task 1.**
  load_records reads `values_ensemble` (real value ens; sigma=0 when present);
  fit_cell adds 0-insertion at -35 BP (config advanced.gam_zinsert_frac, default
  0.05). Backward-compatible: single-vector JSON still works (synthetic sigma).
- `scripts/prepare_realens.R`: gam now routes to ensemble_dcc.rds (was
  singlevec.json); SCC stays single-vector.

## NEXT TASKS (in priority order)

### 1. GAM fix — DONE + FIXED (2026-07-03). maxD 0.259 -> 0.155.
Two dead ends first, then the fix. (a) The scoped modern-anchor port of
`gam_ensemble.py::_compute_anomaly` was written+tested
(`gam_port_refs/gam_modern_FAITHFUL_attempt.py`) and made it WORSE (0.782); the
anchor is NOT the residual (full decomposition in VALIDATION.md). (b) The actual
fix is the phase-consistent one — REAL VALUE ensembles + a faithful 0-insertion:
  - load_records reads the real per-record `values_ensemble` (temp12kEnsemble
    value matrix from emit_realens_json.R on fts_dcc.rds, 779 records) and draws
    those calibration realisations instead of single-vector + synthetic sigma.
    Fixes the uncertainty band: **spread 0.977 -> 0.999**.
  - fit_cell 0-insertion at -35 BP (frac 0.05) pins each cell through 0 near
    present, fixing the recent-end registration that WAS the old maxD.
  - Keeps the paper's Gaussian AGE model (cell 24+38). Feeding the raw chronology
    ensembles (real ages) over-smears the deglacial (12ka ~0.3 warm) -> use real
    VALUES only. Result maxD **0.155** (RMSE 0.038; the maxD is one bin at 11300
    BP; amp 1.105 residual). Test cmd:
```
Rscript reproduction/localrepro/emit_realens_json.R --slim reproduction/localrepro/cache/fts_dcc.rds \
  --out /tmp/proxy_ts_gam_realens.json --ncols 100     # (R_LIBS_USER=...rlib-f7268c4)
reproduction/localrepro/venv/bin/python scripts/gam_method.py \
  --ts /tmp/proxy_ts_gam_realens.json --config config/user_config.yml \
  --grid reference_data/equal_area_grid_centers.csv \
  --sigma-table reference_data/proxy_uncertainties.csv \
  --modern-grid reference_data/worldclim_modern_1deg.csv --out-csv /tmp/gam.csv
python3 reproduction/ci/cmp.py --method gam --csv /tmp/gam.csv        # maxD 0.155
```

### 2. Phase-5 containerization — DONE + CI-VALIDATED (2026-07-04)
Bundle built, image builds/runs, validated in a REAL container on native amd64
via GitHub Actions (`.github/workflows/validate-realens.yml`): downloads the
bundle from the `realens-bundle-v1.0.0` release, builds the image, runs each
method PRESTO_REALENS=1 x2, scores vs published + asserts maxD ceiling +
byte-determinism. CI run 28697594064 = ALL 5 green: SCC 0.091, DCC 0.101,
GAM 0.118, CPS 0.152, PaiCo 0.107, all byte-identical. Local container runs hit
Apple-Silicon EMULATION limits only (GAM pool deadlock -> ncores=1; DCC OOM at
8GB) -- native amd64 CI is clean. Fixes committed: entrypoint.sh renv (run
prepare_realens.R from /), gam_method.py thread-pin + gam_mp_context,
**SCC all-NA fix** (route to ensemble_dcc.rds + cross-cell median, see
VALIDATION.md). Release/run gh cmds need `--repo nickmckay/...` (upstream is
DaveEdge1) and the `workflow` token scope to push workflow files.
Remaining: rebuild the bundle from v1.0.2 lpds for production (pickle = fallback).

### 3. Optional CPS residual (0.131, small) + PaiCo spread (0.70, target-limited)
Both understood and documented; low priority.

## Merge decision
Branch is ready for review. It changes shipping scripts (guarded/backward-
compatible defaults) + adds the container real-ensemble path + all localrepro
tooling. Nothing merged to main yet.
