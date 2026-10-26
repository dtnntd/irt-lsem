# HNUE Journal manuscript — IRT–LSEM Phase 1

LaTeX source for the Vietnamese-language manuscript prepared for **HNUE Journal of Science** (<https://hnuejs.edu.vn>).

## Build

```bash
make pdf            # latexmk -xelatex -> main.pdf
make watch          # live preview, auto-rebuild on save
make clean          # remove aux files
make count_pages    # page count
make count_words    # rough sanity check
make verify         # smoke test: page count + section presence + repo link
```

Requires XeLaTeX + `latexmk` (TeX Live or TinyTeX) with `fontspec`, `polyglossia`, `mathptmx`,
`rsfs`, and the **Times New Roman** font installed on the system (Debian/Ubuntu:
`ttf-mscorefonts-installer`). TinyTeX: `tlmgr install rsfs`.

## Format compliance

This manuscript follows the journal's Vietnamese-article template
(`Mau bao cao Tieng Viet.docx`). Constraints enforced by `main.tex` / `style/hnue.sty`:

- Paper 19 × 27 cm; margins top 2.5 / bottom 2 / inside 3 / outside 1 cm (mirrored);
  header/footer 1.5 cm; page number left on even, right on odd pages.
- Times New Roman 11 pt body, single line spacing, 0.75 cm first-line indent, 2 pt before/after.
- Headings: section 14 pt, subsection 12 pt, sub-subsection 11 pt, bold.
- Title UPPERCASE bold 11 pt; author 12 pt; affiliation italic 11 pt;
  Tóm tắt / Từ khóa 10 pt. Received/revised/accepted dates and corresponding author
  as an unmarked footnote on page 1.
- References: numbered by order of appearance, formatted by `style/hnue.bst`
  ("Tác giả, năm. Tên bài. *Tạp chí*. Vol. xx, Số. xx, tr. xx–xy."); at least one
  HNUE Journal of Science article cited.
- English ABSTRACT (title, author, affiliation, abstract, keywords) at the end, after references.
- Tables: caption above; figures: caption below; both bold italic ("Bảng 1.", "Hình 1.").

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
