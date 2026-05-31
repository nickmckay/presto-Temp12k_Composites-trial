#!/usr/bin/env Rscript
# Dump every record's (lat, lon, dataSetName) so the host can do a WorldClim
# modern-temperature lookup via latlon_utils. Designed to run inside the
# presto-temp12k container against the same slim cache the rest of the GAM
# pipeline reads.
suppressWarnings(suppressPackageStartupMessages({ library(purrr) }))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a
args <- commandArgs(trailingOnly = TRUE)
getarg <- function(flag, d) { i <- which(args == flag); if (length(i)) args[i + 1] else d }
OUT  <- getarg("--out", "/repro/out")
SLIM <- file.path(OUT, "fts_scc.rds")

cat("[dump_latlon] loading slim cache ...\n")
s <- readRDS(SLIM)
fTS <- s$fTS; lat <- s$lat; lon <- s$lon
dsn <- vapply(fTS, function(t) as.character(t$dataSetName %||% NA)[1], character(1))
df <- data.frame(record_index = seq_along(fTS), lat = lat, lon = lon, dataSetName = dsn)
out_path <- file.path(OUT, "record_latlon.csv")
write.csv(df, out_path, row.names = FALSE)
cat(sprintf("[dump_latlon] wrote %s  (%d records)\n", out_path, nrow(df)))
