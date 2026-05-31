#!/usr/bin/env python3
"""Run on the HOST. Reads the 12 WorldClim 10-arcmin monthly tavg GeoTIFFs
(in _repro/_worldclim/wc2.1_10m_tavg.zip), computes the annual mean tavg,
then bilinear-interpolates that field at each Temp12k record's (lat, lon).
Output is read by gam_dump.R as the fallback anchor for records with <100
samples in 3-5 ka.

Inputs:  _repro/out/record_latlon.csv     (record_index, lat, lon, dataSetName)
         _repro/_worldclim/wc2.1_10m_tavg.zip
Outputs: _repro/proxy_modern_refs.csv     (record_index, modern_temp_C)
"""
import io, sys, zipfile
from pathlib import Path
import numpy as np
import pandas as pd
from PIL import Image

REPO = Path(__file__).resolve().parent
INP = REPO / "out" / "record_latlon.csv"
ZIP_PATH = REPO / "_worldclim" / "wc2.1_10m_tavg.zip"
OUT = REPO / "proxy_modern_refs.csv"

NODATA = -3.4e38                                         # WorldClim float32 nodata sentinel
LAT0, LAT1 = 90.0, -90.0                                  # WorldClim arrays are north-up
LON0, LON1 = -180.0, 180.0


def read_monthly_tif(zf, name):
    with zf.open(name) as f:
        return np.array(Image.open(io.BytesIO(f.read())), dtype=np.float32)


# 1) read & average 12 monthly tavg GeoTIFFs
print("[fetch] reading 12 WorldClim monthly tavg tifs ...", flush=True)
with zipfile.ZipFile(ZIP_PATH) as zf:
    names = sorted(n for n in zf.namelist() if n.endswith(".tif"))
    if len(names) != 12:
        sys.exit(f"expected 12 monthly tifs, got {len(names)}: {names}")
    monthly = [read_monthly_tif(zf, n) for n in names]

stack = np.stack(monthly, axis=0)                         # (12, n_lat, n_lon)
stack = np.where(stack < -300, np.nan, stack)             # mask nodata (-3.4e38 -> NaN)
annual = np.nanmean(stack, axis=0)                        # (n_lat, n_lon)
print(f"[fetch] annual tavg grid: shape {annual.shape}, "
      f"range [{np.nanmin(annual):.1f}, {np.nanmax(annual):.1f}] degC, "
      f"{np.isfinite(annual).sum()} valid pixels", flush=True)

n_lat, n_lon = annual.shape
dlat = (LAT0 - LAT1) / n_lat                              # 180 / n_lat (positive)
dlon = (LON1 - LON0) / n_lon                              # 360 / n_lon (positive)

# 2) bilinear-interpolate at each record's (lat, lon); fall back to nearest non-NaN within 50 km
df = pd.read_csv(INP)
lats = df["lat"].to_numpy(float)
lons = df["lon"].to_numpy(float)


def sample(lat, lon):
    if not np.isfinite(lat) or not np.isfinite(lon):
        return np.nan
    # row index increases southward; col index increases eastward
    rf = (LAT0 - lat) / dlat
    cf = (lon - LON0) / dlon
    r0 = int(np.floor(rf)); c0 = int(np.floor(cf))
    if r0 < 0 or r0 >= n_lat - 1 or c0 < 0 or c0 >= n_lon - 1:
        # rough wrap-around clamp; record nearest valid pixel
        r0 = max(0, min(n_lat - 1, r0)); c0 = max(0, min(n_lon - 1, c0))
        return float(annual[r0, c0])
    dr = rf - r0; dc = cf - c0
    block = annual[r0:r0 + 2, c0:c0 + 2]
    if not np.isfinite(block).all():
        # find nearest non-NaN within a 5-pixel neighbourhood (~50 km at 10 arcmin)
        for k in range(1, 6):
            r_lo, r_hi = max(0, r0 - k), min(n_lat, r0 + k + 1)
            c_lo, c_hi = max(0, c0 - k), min(n_lon, c0 + k + 1)
            nb = annual[r_lo:r_hi, c_lo:c_hi]
            if np.isfinite(nb).any():
                return float(np.nanmean(nb))
        return np.nan
    return float((1 - dr) * (1 - dc) * block[0, 0] +
                 (1 - dr) * dc * block[0, 1] +
                 dr * (1 - dc) * block[1, 0] +
                 dr * dc * block[1, 1])


modern = np.array([sample(la, lo) for la, lo in zip(lats, lons)])

out = pd.DataFrame({"record_index": df["record_index"], "modern_temp_C": modern})
out.to_csv(OUT, index=False)
n_valid = int(np.isfinite(modern).sum())
print(f"[fetch] wrote {OUT}  ({n_valid}/{len(out)} valid lookups)")
if n_valid < len(out):
    miss = df[~np.isfinite(modern)]
    print(f"[fetch] missing records: {miss['dataSetName'].head(5).tolist()} ...")
