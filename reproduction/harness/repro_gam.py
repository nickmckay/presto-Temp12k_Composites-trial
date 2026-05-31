#!/usr/bin/env python3
"""GAM stage 2: read pooled (age, temp, cell, band) samples, fit one LinearGAM
per cell on the pooled ensemble cloud (matches the published gam_ensemble.py),
draw n_draws posterior samples per cell, aggregate cells->band (equal-area grid
mean) and bands->global (sin-area weights), apply the archival reference.

Output: gam_global.csv (binAges + nens columns) matching the R harness schema.
"""
import argparse
import os
import sys
import numpy as np
import pandas as pd
from pygam import LinearGAM, s

ap = argparse.ArgumentParser()
ap.add_argument("--inp", default="/repro/out/gam_pooled.csv")
ap.add_argument("--out", default="/repro/out/gam_global.csv")
ap.add_argument("--nens", type=int, default=50)
ap.add_argument("--ncores", type=int, default=12)
a = ap.parse_args()

LATBINS = np.arange(-90, 91, 30)
N_BANDS = 6
ZW = np.sin(LATBINS[1:] * np.pi / 180) - np.sin(LATBINS[:-1] * np.pi / 180); ZW /= ZW.sum()
binvec = np.arange(-50, 12051, 100, dtype=float)
bin_ages = (binvec[:-1] + binvec[1:]) / 2.0
NB = bin_ages.size

print(f"[gam] loading {a.inp} ...", flush=True)
d = pd.read_csv(a.inp)
print(f"[gam] {len(d):,} points, {d['cell'].nunique()} cells, "
      f"age {d['age'].min():.0f}-{d['age'].max():.0f}", flush=True)


def fit_cell(grp_xy_band):
    """Fit one cell. Returns (cid, draws_mu (NB, n_draws), scale, band) so noise
    gain can be applied post-hoc without re-fitting the GAM."""
    cid, x, y, pre_anom, band = grp_xy_band
    if x.size < 20 or np.ptp(x) < 200:
        return cid, None, None, band
    ref_mask = (x >= 3000) & (x <= 5000)
    if ref_mask.sum() < 100:
        return cid, None, None, band
    # Cell-level 3-5 ka anchor: published _compute_anomaly L506-509 computes the
    # mean over the ALIGNED SUBSET of the cell pool only. pre_anom records have
    # already had their per-record 3-5 ka mean subtracted (their values are
    # anomalies near 0 around 3-5 ka), so including them in the cell-level
    # anchor distorts the variance structure. Mask them out of the anchor calc.
    anchor_mask = ref_mask & ~pre_anom.astype(bool)
    if anchor_mask.sum() < 100:                              # all candidates were pre-anomalized
        anchor_mask = ref_mask
    y0 = y - np.nanmean(y[anchor_mask])
    try:
        # Constrain pygam lam grid to remove the wiggly low-lam tail that pygam
        # 0.12 sometimes selects (over-amplifies the GAM curve vs pygam 0.8 used
        # by the published archive).
        lam_grid = np.logspace(-1, 3, 11)
        gam = LinearGAM(s(0)).gridsearch(x[:, None], y0, lam=lam_grid, progress=False)
        draws = gam.sample(x[:, None], y0, sample_at_X=bin_ages[:, None],
                           n_draws=a.nens, n_bootstraps=1, quantity="mu")
        resid = y0 - gam.predict(x[:, None])
        scale = float(np.nanstd(resid))
        outside = (bin_ages < x.min()) | (bin_ages > x.max())
        draws[:, outside] = np.nan
        counts, _ = np.histogram(x, bins=binvec)
        surrounding = np.convolve(counts, np.ones(3, dtype=int), mode="same")
        draws[:, surrounding < 100] = np.nan
        return cid, draws.T, scale, band                # (NB, n_draws), scalar
    except Exception as exc:
        print(f"[gam] cell {cid}: {exc}", file=sys.stderr)
        return cid, None, None, band


# Pre-extract per-cell numpy arrays, then fit in parallel
groups = []
for cid, grp in d.groupby("cell"):
    groups.append((int(cid),
                   grp["age"].to_numpy(float),
                   grp["temp"].to_numpy(float),
                   grp["pre_anomalized"].to_numpy(int) if "pre_anomalized" in grp.columns
                       else np.zeros(len(grp), dtype=int),
                   int(grp["band"].iloc[0])))
print(f"[gam] fitting {len(groups)} cells on {a.ncores} cores ...", flush=True)

# imap_unordered + per-result progress so we see actual liveness (and which cell
# stalls if a fit hangs). Chunk size 1 so progress is fine-grained.
import multiprocessing as mp
import time
cell_draws_mu = {}
cell_scale = {}
cell_band = {}
n_done = 0; n_skipped = 0; t0 = time.time()
with mp.get_context("fork").Pool(a.ncores) as pool:
    for cid, dr, sc, band in pool.imap_unordered(fit_cell, groups, chunksize=1):
        cell_band[cid] = band
        if dr is None:
            n_skipped += 1
        else:
            cell_draws_mu[cid] = dr
            cell_scale[cid] = sc
        n_done += 1
        if n_done % 10 == 0 or n_done == len(groups):
            elapsed = time.time() - t0
            rate = n_done / elapsed if elapsed > 0 else 0
            eta = (len(groups) - n_done) / rate if rate > 0 else 0
            print(f"[gam] {n_done}/{len(groups)} cells fit ({n_skipped} skipped), "
                  f"{elapsed:.0f}s elapsed, ETA {eta:.0f}s", flush=True)
print(f"[gam] fit {len(cell_draws_mu)} cells, skipped {n_skipped}", flush=True)

# Sweep noise gains in one process -- pygam 0.12's quantity='y' inflates the
# scale_ estimate 3x vs the pygam 0.8 the published archive used. We sample mu
# (smooth function only) and add empirical-residual-std * GAIN noise per draw
# per bin, sweeping GAIN to calibrate against the published spread~1.0.
gains_str = os.environ.get("GAM_FIT_NOISE_GAINS", "1.0")  # gain=1.0 calibrated against
# published spread~1.0; pygam 0.12's quantity='y' inflates scale_ 3x vs the published
# pygam 0.8, so we use quantity='mu' + manual noise = empirical-residual-std * gain.
gains = [float(g) for g in gains_str.split(",") if g.strip()]
out_base = a.out[:-4] if a.out.endswith(".csv") else a.out


def aggregate(cell_draws):
    band_ens = np.full((NB, N_BANDS, a.nens), np.nan)
    for b in range(N_BANDS):
        cells_b = [c for c, bn in cell_band.items() if bn == b + 1 and c in cell_draws]
        if not cells_b:
            continue
        arr = np.stack([cell_draws[c] for c in cells_b], axis=0)
        band_ens[:, b, :] = np.nanmean(arr, axis=0)
    glob = np.full((NB, a.nens), np.nan)
    for k in range(a.nens):
        bm = band_ens[:, :, k]
        w = np.tile(ZW, (NB, 1)).astype(float); w[~np.isfinite(bm)] = np.nan
        num = np.nansum(bm * w, axis=1); den = np.nansum(w, axis=1)
        glob[:, k] = np.where(den > 0, num / den, np.nan)
    glob = glob - np.nanmean(glob, axis=0, keepdims=True)
    r100 = int(np.argmin(np.abs(bin_ages - 100)))
    glob = glob - np.nanmedian(glob[r100, :])
    return glob


for gain in gains:
    cd = {}
    for cid, dr in cell_draws_mu.items():
        sc = cell_scale[cid]
        if gain > 0 and np.isfinite(sc) and sc > 0:
            rng = np.random.default_rng(seed=cid * 17 + 1)
            nan_mask = ~np.isfinite(dr)
            d2 = dr + rng.normal(0.0, sc * gain, size=dr.shape)
            d2[nan_mask] = np.nan
            cd[cid] = d2
        else:
            cd[cid] = dr
    glob = aggregate(cd)
    out = a.out if len(gains) == 1 else f"{out_base}_g{gain:g}.csv"
    df = pd.DataFrame(glob, columns=[f"ens{i+1}" for i in range(a.nens)])
    df.insert(0, "binAges", bin_ages)
    df.to_csv(out, index=False)
    print(f"[gam] gain={gain:g}: wrote {out}", flush=True)
