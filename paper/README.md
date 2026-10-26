# HNUE Journal manuscript — IRT–LSEM Phase 1

LaTeX source for the Vietnamese-language manuscript submitted to **HNUE Journal of Science** (<https://hnuejs.edu.vn>).

## Build

```bash
make pdf            # latexmk -> main.pdf
make watch          # live preview, auto-rebuild on save
make clean          # remove aux files
make count_pages    # verify <= 10 pages (HNUE limit)
make count_words    # rough sanity check
make verify         # smoke test: page count + section presence + repo link
```

Requires `latexmk`, `texlive-latex-extra`, `texlive-lang-vietnamese`, `texlive-fonts-recommended`.
On Debian/Ubuntu:

```bash
sudo apt-get install texlive-latex-extra texlive-lang-vietnamese texlive-fonts-recommended latexmk
```

## Format compliance

This manuscript follows the HNUE Journal of Science format spec encoded in the
[`hnue-journal-format`](~/.claude/skills/hnue-journal-format/SKILL.md) skill.
Headline constraints enforced by `main.tex`/`style/hnue.sty`:

- Paper 19 × 27 cm, margins 3 / 2.5 / 2 / 1 cm.
- Times New Roman 12 pt body, single line spacing, 0.75 cm indent, 2 pt before/after.
- Section headings 14 pt bold, subsections 13 pt / 12 pt.
- Numeric `[n]` citations via `\bibliographystyle{ieeetr}`.
- Bilingual VI/EN metadata + abstract in 2 columns.
- Tables: caption above (bold italic, centered). Figures: caption below.

## Figure source mapping

| Figure file (paper/figures/) | Source in irt_lsem outputs |
|---|---|
| `pipeline.pdf` | Hand-drawn TikZ (in `figures/pipeline.tex`) summarising B0→B7 |
| `lgcm_lcsm_grade.pdf` | Composite of `outputs/b5_report/fig_lgcm_trajectories.png` + `fig_lcsm_coupling.png` |
| `kalman_overlay_g12.pdf` | Re-rendered with anonymous label "Student A" from `outputs/b6_kalman/plots/kalman_overlay_grade_12.png` |
| `ctdsem_ou_g12.pdf` | TikZ phase portrait drawn from `outputs/b5_report/final_ctdsem_population.csv` |
| `early_warning_distribution.pdf` | Generated from `outputs/b5_report/final_early_warning_summary.csv` |

Privacy: all paper figures use **aggregate or anonymised data**. No raw per-student identifiers
appear in the published manuscript.

## License

- Paper text and figures: **CC-BY-4.0** (manuscript-level licence, separate from code).
- LaTeX source files in this folder: covered by the repository root `LICENSE` (MIT).
