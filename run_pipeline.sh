#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "============================================"
echo "  IRT-LSEM Pipeline — Phase 1 (2024-2025)"
echo "============================================"

echo ""
echo "=== B0: Preprocessing (Python) ==="
uv run python src/python/b0_preprocess.py
uv run python src/python/verify/verify_b0.py || { echo "❌ B0 verification FAILED"; exit 1; }
echo "✅ B0 passed"

echo ""
echo "=== B1: Dimensionality (R) ==="
Rscript src/r/b1_dimensionality.R
Rscript src/r/verify/verify_b1.R || { echo "❌ B1 verification FAILED"; exit 1; }
echo "✅ B1 passed"

echo ""
echo "=== B2: IRT Calibration (R) ==="
Rscript src/r/b2_calibration.R
Rscript src/r/verify/verify_b2.R || { echo "❌ B2 verification FAILED"; exit 1; }
echo "✅ B2 passed"

echo ""
echo "=== B3: EAP Scoring (R) ==="
Rscript src/r/b3_eap_scoring.R
Rscript src/r/verify/verify_b3.R || { echo "❌ B3 verification FAILED"; exit 1; }
echo "✅ B3 passed"

echo ""
echo "=== B4: LSEM Fitting (R) ==="
Rscript src/r/b4a_lgcm_lcsm.R
Rscript src/r/b4c_ctdsem.R
echo "✅ B4 done"

echo ""
echo "=== B5: Consolidate + diagnostic plots (no render yet) ==="
Rscript src/r/b5_consolidate.R
Rscript src/r/b0_plots.R
Rscript src/r/b2_plots.R
Rscript src/r/b3_plots.R
Rscript src/r/b4a_viz.R
Rscript src/r/b4c_viz.R
Rscript src/r/b5_plots.R
echo "✅ B5 consolidate + plots done"

echo ""
echo "=== B6: Kalman Smoother (R) ==="
Rscript src/r/b6_kalman.R
Rscript src/r/b6_viz.R
Rscript src/r/verify/verify_b6.R || { echo "❌ B6 verification FAILED"; exit 1; }
echo "✅ B6 passed"

echo ""
echo "=== B7: Applications (R) ==="
Rscript src/r/b7a_early_warning.R
Rscript src/r/b7b_recommendation.R
Rscript src/r/verify/verify_b7.R || { echo "❌ B7 verification FAILED"; exit 1; }
echo "✅ B7 passed"

echo ""
echo "=== B5 final: re-consolidate (pick up B6/B7) + render + verify ==="
Rscript src/r/b5_consolidate.R
Rscript -e "rmarkdown::render('src/r/b5_report.Rmd', output_dir = 'outputs/b5_report/')"
Rscript src/r/b5_verify_final.R || { echo "❌ B5 final verification FAILED"; exit 1; }
echo "✅ B5 final done"

echo ""
echo "============================================"
echo "  Pipeline complete!"
echo "============================================"
