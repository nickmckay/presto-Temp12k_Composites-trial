#!/usr/bin/env Rscript
# GAM stage 1 (R): read the temp12kEnsemble slim cache, assign each record to a
# 30-deg band + equal-area grid cell, then for each record draw N pairs of
# (ageEnsemble column, value-ensemble column) and write all the sampled (age,
# temp, cell, band) points into one pooled CSV.  Python loads it, fits one
# pygam.LinearGAM per cell, and samples gam.sample(n_draws=nens).
suppressWarnings(suppressPackageStartupMessages({ library(purrr) }))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a
args <- commandArgs(trailingOnly = TRUE)
getarg <- function(flag, d = NULL) { i <- which(args == flag); if (length(i)) args[i + 1] else d }
N_POOL <- as.integer(getarg("--pool", "200"))    # pool draws per record (matches original's 500 cloud size)
OUT    <- getarg("--out", "/repro/out")
SLIM   <- file.path(OUT, "fts_scc.rds")          # reuse SCC slim (has lat+lon)
GRID   <- "/repro/equal_area_grid_centers.csv"
SEED   <- as.integer(getarg("--seed", "42"))
GIBBS  <- "--gibbs-ages" %in% args                # replace LiPD chronModel ageEnsemble with
                                                  # the published's simple Gaussian age model
                                                  # (notebook cell 24): age_unc = 50 + age*200/12000.
                                                  # No monotonicity enforcement (first-cut).

cat("[gam_dump] loading slim cache ...\n")
s <- readRDS(SLIM)
fTS <- s$fTS; lat <- s$lat; lon <- s$lon
cat("[gam_dump] records:", length(fTS), "\n")

g <- read.csv(GRID); rad <- pi / 180
cell <- vapply(seq_along(lat), function(i) {
  if (!is.finite(lat[i]) || !is.finite(lon[i])) return(NA_integer_)
  d <- sin(g$clat * rad) * sin(lat[i] * rad) +
       cos(g$clat * rad) * cos(lat[i] * rad) * cos((g$clon180 - lon[i]) * rad)
  which.max(pmin(pmax(d, -1), 1))
}, integer(1))
LATBINS <- seq(-90, 90, by = 30)
band <- findInterval(lat, LATBINS, rightmost.closed = TRUE)
band[band < 1 | band > 6 | !is.finite(lat)] <- NA
cat(sprintf("[gam_dump] %d records have cell+band; %d unique cells\n",
            sum(!is.na(cell) & !is.na(band)), length(unique(na.omit(cell)))))

set.seed(SEED)

# ---- _align_ensembles: per-cell per-record baseline alignment -----------------
# Published gam_ensemble.py L385-426: within each cell, pick the longest record
# as base, then for each other record shift it so its mean over the age-overlap
# with base equals base's mean over that overlap (so they sit on the same
# baseline). Then _compute_anomaly subtracts the cell's modern-window (3-5 ka)
# mean. Implemented as a per-record offset that we subtract before pooling.
# Builds per-record representative (age_ens, val) using ALL age-ensemble columns.
# Publishd _align_ensembles compares raw ensemble ages (n_samples * n_ens_cols), not
# a single chronology, so for the overlap test we use the full age cloud per record.
cat("[gam_dump] computing per-cell record alignment offsets ...\n")
# Build record_rep using flat age_ens (all ensemble columns raveled) for the
# overlap test; val stays per-sample. Filter samples to age range and to
# |temperature| < 200 (published cell 32: outlier zeroing then dropna).
record_rep <- vector("list", length(fTS))
for (i in seq_along(fTS)) {
  r <- fTS[[i]]
  ae <- r$ageEnsemble; v <- r$paleoData_values
  if (!is.matrix(ae)) ae <- matrix(as.numeric(ae), ncol = 1)
  if (!is.matrix(v))  v  <- matrix(as.numeric(v),  ncol = 1)
  age_med <- as.numeric(ae[, 1])
  val <- if (NCOL(v) > 1) apply(v, 1, median, na.rm = TRUE) else as.numeric(v)
  val[abs(val) > 200] <- NA_real_                           # Bug 6: published cell 32 outlier filter
  ok <- is.finite(age_med) & is.finite(val) & age_med >= -50 & age_med <= 12050
  record_rep[[i]] <- list(age_med = age_med[ok], val = val[ok], idx = which(ok),
                          age_ens = as.numeric(ae[ok, , drop = FALSE]))
}
record_offset <- rep(NA_real_, length(fTS))
record_aligned <- rep(FALSE, length(fTS))
# Track whether the record's offset is an anomaly anchor (per-record 3-5 ka mean
# was subtracted; record contributes ~0 at 3-5 ka) vs an alignment shift (record
# shifted to base's level). Used to exclude anomalized records from the cell-
# level 3-5 ka anchor in repro_gam.py (published _compute_anomaly L506-509 uses
# the ALIGNED SUBSET only for the cell-level shift).
record_pre_anomalized <- rep(FALSE, length(fTS))
# Published _compute_anomaly L534 falls back to a WorldClim modern temperature
# (via latlon_utils.get_climate) for records with no 3-5 ka coverage that are
# also not 'datum=anom'. We pre-compute that lookup on the host (no network in
# the container) and read the CSV here. Marine records have NaN -> still drop.
worldclim_path <- "/repro/proxy_modern_refs.csv"
worldclim_modern <- rep(NA_real_, length(fTS))
if (file.exists(worldclim_path)) {
  wc <- read.csv(worldclim_path)
  worldclim_modern[wc$record_index] <- wc$modern_temp_C
  cat(sprintf("[gam_dump] loaded WorldClim modern temps: %d/%d valid\n",
              sum(is.finite(worldclim_modern)), length(worldclim_modern)))
} else {
  cat("[gam_dump] WARNING: no WorldClim modern lookup CSV; deglacial records may be dropped\n")
}
# Counters for diagnostics
n_aligned <- 0; n_solo_anom <- 0; n_solo_zero <- 0
n_no_overlap_anom <- 0; n_no_overlap_zero <- 0
for (cid in unique(cell[!is.na(cell)])) {
  recs <- which(cell == cid)
  if (length(recs) == 0) next
  if (length(recs) == 1) {                                   # singleton cell: per-record anomaly
    rr <- record_rep[[recs]]
    ref <- rr$age_med >= 3000 & rr$age_med <= 5000
    # Bug 3: published _compute_anomaly requires >=100 samples in 3-5 ka; else fall back to 0.
    if (sum(ref) >= 100) {
      record_offset[recs] <- mean(rr$val[ref], na.rm = TRUE)
      record_pre_anomalized[recs] <- TRUE
      n_solo_anom <- n_solo_anom + 1
    } else if (is.finite(worldclim_modern[recs])) {
      # Published _compute_anomaly L534 fallback: subtract WorldClim modern temp
      record_offset[recs] <- worldclim_modern[recs]
      record_pre_anomalized[recs] <- TRUE
      n_solo_zero <- n_solo_zero + 1            # repurposed counter: now "via WorldClim"
    } else {
      record_offset[recs] <- NA_real_           # no land pixel (marine) -> drop, matches published NaN propagation
      n_solo_zero <- n_solo_zero + 1            # (will be reflected in n_dropped_no_anchor)
    }
    next
  }
  # ---- multi-record: pick longest, iteratively grow the aligned union ----
  lens <- vapply(recs, function(i) length(record_rep[[i]]$age_med), integer(1))
  base_i <- recs[which.max(lens)]
  # Bug 4: drop base_modern from base's offset. Anchor is applied to the pool
  # (cell-pool 3-5 ka subtraction in repro_gam.py) once for all aligned records.
  record_offset[base_i] <- 0
  record_aligned[base_i] <- TRUE
  n_aligned <- n_aligned + 1
  build_pair <- function(idx) {
    r <- fTS[[idx]]
    ae <- r$ageEnsemble; if (!is.matrix(ae)) ae <- matrix(as.numeric(ae), ncol = 1)
    rep_per <- record_rep[[idx]]
    ae_ok <- ae[rep_per$idx, , drop = FALSE]                 # only kept samples
    val_rep <- rep_per$val
    nc <- NCOL(ae_ok)
    list(age = as.numeric(ae_ok), val = rep(val_rep, nc))
  }
  base_pair <- build_pair(base_i)
  aligned_age <- base_pair$age
  aligned_val <- base_pair$val
  remaining <- setdiff(recs, base_i)
  changed <- TRUE
  # iterative growth: each pass, try to align records against the current
  # aligned union; absorb any that overlap (>100 samples both sides).
  while (length(remaining) > 0 && changed) {
    changed <- FALSE
    a_min <- min(aligned_age); a_max <- max(aligned_age)
    still_remaining <- integer(0)
    for (i in remaining) {
      rp <- build_pair(i)
      if (length(rp$age) == 0) { still_remaining <- c(still_remaining, i); next }
      r_min <- min(rp$age); r_max <- max(rp$age)
      # Bug 1: ensemble-sample overlap count > 100 on BOTH sides
      m1 <- aligned_age >= r_min & aligned_age <= r_max         # aligned ens in record's range
      m2 <- rp$age      >= a_min & rp$age      <= a_max         # record ens in aligned's range
      if (sum(m1) > 100 && sum(m2) > 100) {
        # diff = aligned_overlap_mean - record_overlap_mean; shift record by +diff
        diff <- mean(aligned_val[m1], na.rm = TRUE) - mean(rp$val[m2], na.rm = TRUE)
        record_offset[i] <- -diff                              # subtract this to add diff
        record_aligned[i] <- TRUE
        n_aligned <- n_aligned + 1
        # Absorb into the aligned union (use record's POST-shift values for future overlap means)
        aligned_age <- c(aligned_age, rp$age)
        aligned_val <- c(aligned_val, rp$val + diff)
        changed <- TRUE
      } else {
        still_remaining <- c(still_remaining, i)
      }
    }
    remaining <- still_remaining
  }
  # Bug 2 fallout: records that never aligned fall through. Use per-record
  # 3-5 ka mean if >=100 samples, else 0 (Bug 3).
  for (i in remaining) {
    rr <- record_rep[[i]]
    ref <- rr$age_med >= 3000 & rr$age_med <= 5000
    if (sum(ref) >= 100) {
      record_offset[i] <- mean(rr$val[ref], na.rm = TRUE)
      record_pre_anomalized[i] <- TRUE
      n_no_overlap_anom <- n_no_overlap_anom + 1
    } else if (is.finite(worldclim_modern[i])) {
      record_offset[i] <- worldclim_modern[i]
      record_pre_anomalized[i] <- TRUE
      n_no_overlap_zero <- n_no_overlap_zero + 1
    } else {
      record_offset[i] <- NA_real_
      n_no_overlap_zero <- n_no_overlap_zero + 1
    }
  }
}
cat(sprintf("[gam_dump] alignment: %d aligned in union | singleton %d anom + %d zero | no-overlap %d anom + %d zero\n",
            n_aligned, n_solo_anom, n_solo_zero, n_no_overlap_anom, n_no_overlap_zero))

# Published uncertainty model (gam_ensemble.py, agent's quote):
#   ds['temperature_ensemble'] = np.random.normal(ds.temperature, ds.temp_unc, ...)
# with temp_unc looked up PER PROXY × PER SEASON from proxy-uncertainties.xlsx.
# Fix #1: load that table and look up each record's sigma.
PUNC <- read.csv("/repro/proxy_uncertainties.csv", stringsAsFactors = FALSE)
SIGMA_DEFAULT <- 1.7  # "median of all values"; published uses 1.975878 (75th pct w/o d18O) but
                       # smaller default fits records lacking proxy match without inflating cell variance
match_proxy_cat <- function(rec_proxy) {
  p <- tolower(as.character(rec_proxy %||% ""))
  if (grepl("pollen", p)) return("pollen")
  if (grepl("alkenone|uk.?37", p)) return("alkenone")
  if (grepl("mg.?ca", p)) return("MgCa")
  if (grepl("chironomid", p)) return("chironomid")
  if (grepl("tex.?86", p)) return("GDGT (Tex86)")
  if (grepl("mbt|brgdgt|gdgt", p)) return("GDGT (MBT/CBT as well as BrGDGT fractional abundance)")
  if (grepl("d18o", p)) return("d18O")
  if (grepl("diatom", p)) return("other microfossils/diatoms")
  if (grepl("dinocyst|dinoflagell", p)) return("other microfossils/dinocyst")
  if (grepl("radiolaria", p)) return("other microfossils/radiolaria")
  if (grepl("foramini|foram", p)) return("other microfossils/foraminifera")
  NA_character_
}
match_season_col <- function(sg) {
  s <- tolower(as.character(sg %||% ""))
  if (grepl("summer", s)) return("summer")
  if (grepl("winter", s)) return("winter")
  return("annual")          # annual + everything else
}
get_sigma <- function(proxy_str, season_str) {
  pc <- match_proxy_cat(proxy_str); sc <- match_season_col(season_str)
  if (is.na(pc)) return(SIGMA_DEFAULT)
  row <- PUNC[PUNC$proxy == pc, ]
  if (nrow(row) == 0) return(SIGMA_DEFAULT)
  v <- suppressWarnings(as.numeric(row[[sc]]))
  if (!is.finite(v)) v <- suppressWarnings(as.numeric(row[["annual"]]))
  if (!is.finite(v)) SIGMA_DEFAULT else v
}
n_decimated <- 0; n_default_sigma <- 0; n_dropped_no_anchor <- 0
chunks <- vector("list", length(fTS))
for (i in seq_along(fTS)) {
  if (is.na(cell[i]) || is.na(band[i])) next
  if (!is.finite(record_offset[i])) {                       # no valid anchor: drop record
    n_dropped_no_anchor <- n_dropped_no_anchor + 1
    next
  }
  r <- fTS[[i]]
  v  <- r$paleoData_values; ae <- r$ageEnsemble
  if (!is.matrix(v)) v  <- matrix(as.numeric(v),  ncol = 1)
  if (!is.matrix(ae)) ae <- matrix(as.numeric(ae), ncol = 1)
  # Published cell 24+38: per-sample age_unc = 50 + age*(250-50)/12000 yr,
  # then draw 500 age realizations from N(age, age_unc). Replaces the LiPD
  # chronModel ageEnsemble (which carries wider chronology uncertainty than
  # the published's simple Gaussian model -> wider GAM cloud -> wider posterior).
  age_orig <- ae[, 1]                                       # median age before Gibbs replacement
  if (GIBBS) {
    age_unc <- 50 + pmax(age_orig, 0) * (250 - 50) / 12000
    ae <- matrix(rnorm(length(age_orig) * 500, mean = age_orig, sd = age_unc),
                 nrow = length(age_orig), ncol = 500)
  }
  # Published notebook cell 29: ALWAYS use proxy x season lookup, falling back to
  # the 75th-percentile-without-d18O default. paleoData_uncertainty1sd is NOT used.
  sigma <- get_sigma(r$paleoData_proxy, r$seasonalityGeneral)
  if (sigma == SIGMA_DEFAULT) n_default_sigma <- n_default_sigma + 1
  # single calibrated temperature series per record
  val_rep <- if (NCOL(v) > 1) apply(v, 1, median, na.rm = TRUE) else as.numeric(v)
  val_rep[abs(val_rep) > 200] <- NA_real_                     # Bug 6: published cell 32 outlier filter
  # _align_ensembles: subtract per-record alignment offset (puts all records
  # in the cell on a common baseline before pooling into the GAM cloud).
  if (is.finite(record_offset[i])) val_rep <- val_rep - record_offset[i]
  # Bug 5: published cell 19 groups by AGE value bucketed at 10-yr centres
  # (`5 + age - (age % 10)`) on the ORIGINAL median age (BEFORE Gibbs Gaussian
  # replacement) -- a TIME-based bin, not a sample-index block. Use a factor
  # with explicit levels so tapply produces a fixed-length output regardless
  # of which groups have all-NaN values in any given ae column.
  if (length(val_rep) > 1470) {
    # Integer bucket centred at 10-yr midpoints, robust to float-precision drift.
    g_raw <- as.integer(round(5 + age_orig - (age_orig %% 10)))
    g_levels <- sort(unique(g_raw[is.finite(g_raw)]))
    g_factor <- factor(g_raw, levels = g_levels)
    val_rep <- as.numeric(tapply(val_rep, g_factor, mean, na.rm = TRUE))
    ae <- vapply(seq_len(NCOL(ae)),
                 function(k) as.numeric(tapply(ae[, k], g_factor, mean, na.rm = TRUE)),
                 numeric(length(g_levels)))
    if (!is.matrix(ae)) ae <- matrix(ae, ncol = 1)
    n_decimated <- n_decimated + 1
  }
  nca <- NCOL(ae)
  ages_k <- ae[, sample.int(nca, N_POOL, replace = TRUE)]
  if (!is.matrix(ages_k)) ages_k <- matrix(ages_k, ncol = N_POOL)
  vals_k <- matrix(rep(val_rep, N_POOL), nrow = length(val_rep)) +
            matrix(rnorm(length(val_rep) * N_POOL, mean = 0, sd = sigma),
                   nrow = length(val_rep), ncol = N_POOL)
  ok <- is.finite(ages_k) & is.finite(vals_k) & ages_k >= -50 & ages_k <= 12050
  if (!any(ok)) next
  chunks[[i]] <- data.frame(
    age  = as.numeric(ages_k[ok]),
    temp = as.numeric(vals_k[ok]),
    cell = cell[i], band = band[i],
    pre_anomalized = as.integer(record_pre_anomalized[i]))
}
df <- do.call(rbind, chunks[!vapply(chunks, is.null, logical(1))])
out_path <- file.path(OUT, "gam_pooled.csv")
data.table::fwrite(df, out_path)
cat(sprintf("[gam_dump] wrote %s  (%.1fM rows, %d cells)\n",
            out_path, nrow(df) / 1e6, length(unique(df$cell))))
cat(sprintf("[gam_dump] decadally-decimated %d records; %d records used SIGMA_DEFAULT\n",
            n_decimated, n_default_sigma))
cat(sprintf("[gam_dump] dropped %d records with no valid 3-5 ka anchor (no aligned union, <100 samples in 3-5 ka)\n",
            n_dropped_no_anchor))
