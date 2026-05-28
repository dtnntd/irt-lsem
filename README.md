# IRT–LSEM — Dynamic Student Ability Estimation

> Integrated **IRT** + **LSEM** + **Kalman smoother** pipeline applied to Vietnamese
> high-school mathematics data from the OLM learning platform (school year 2024–2025).

## Installation

```bash
# Python (preprocessing)
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt   # or `uv sync` if you use uv

# R packages
Rscript -e 'install.packages(c("mirt", "lavaan", "lme4", "ctsem", "KFAS", "rmarkdown", "bit64"))'
```

## Running the pipeline

```bash
bash run_pipeline.sh
```

| Step | Tool | Role | Main outputs |
|------|------|------|--------------|
| B0 | Python | Preprocess + build response_long | `response_long_*.csv`, `day_mapping_*.csv` (private) |
| B1 | R | Unidimensionality check (EFA + scree) | `scree_plot_*.png` |
| B2 | R | IRT 1PL calibration (`mirt`) | `irt_1pl_grade_*.csv` (item bank, public) |
| B3 | R | EAP scoring | `theta_trajectory_*.csv` (private) |
| B4a | R | LGCM/LCSM (`lavaan`) + lmer | `lgcm_params_*.csv`, `lcsm_params_*.csv`, `mlm_*.rds` |
| B4c | R | CT-DSEM, grade 12 (`ctsem`) | `ctdsem_population_params.csv` |
| B5 | R | Consolidate + render report | `b5_report.html`, `final_*.csv` |
| B6 | R | Kalman smoothing (`KFAS`) | `kalman_pop_metrics.csv` + per-student (private) |
| B7 | R | Early-warning + item recommender | `early_warning_*.csv`, `recommendation_*.csv` (private) |

## Reproducibility

Re-running the full pipeline from scratch requires the raw `response_long_*.csv` from OLM
Math collections. Raw data is not published for student-privacy reasons; researchers who need
access for replication purposes may contact the authors.

The aggregate CSVs in `outputs/b5_report/` are sufficient to regenerate **every table and
figure in the manuscript**. Two scripts handle this: `src/r/b5_consolidate.R` (aggregation)
and `src/r/b5_report.Rmd` (report rendering).

## Citation

```bibtex
@article{nguyen2026irtlsem,
  title  = {Real-time estimation of student ability based on Item Response Theory (IRT)
            and Longitudinal Structural Equation Modeling (LSEM)},
  author = {Nguyen, Tien Dat and Nguyen, Diep Linh and Bach, Duc Anh and
            Bui, Thi Thu Thuy and Pham, Le Nhat Linh},
  journal= {HNUE Journal of Science},
  year   = {2026},
  note   = {Submitted}
}
```

## Contact

- **Corresponding author:** Nguyen Tien Dat — `mas835151465@hnue.edu.vn` (primary),
  `datlcpro@gmail.com` (alternative)
- **Principal supervisor:** Assoc. Prof. Pham Tho Hoan
- **Affiliation:** Faculty of Information Technology, School of Mathematics and Information
  Technology, Hanoi National University of Education, Hanoi, Vietnam

## License

**Code** (source in `src/` and pipeline scripts): **MIT** — see [`LICENSE`](LICENSE).
