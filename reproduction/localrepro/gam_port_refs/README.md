# GAM port references (for NEXT TASK 1 in ../HANDOFF.md)

- `gam_ensemble_ORIGINAL.py` — the published GAM_frozen engine (nickmckay/
  Temperature12k GAM_frozen/scripts). The algorithm to port: _compute_anomaly
  (modern-window ensemble alignment, L486+) + _predict_gam 0-insertion at -35 BP
  (L236). Reference curve to match: reference_data/published/gam_published.csv.
- `gam_modern_BROKEN_attempt.py` — this session-s failed crude modern-anchor
  (scalar worldclim subtraction -> maxD 10.8). Shows what NOT to do; the
  original aligns ensembles, it does not subtract absolute worldclim temp.
