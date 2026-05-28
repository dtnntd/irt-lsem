# IRT–LSEM — Ước lượng năng lực động của học sinh

> Pipeline tích hợp **IRT** + **LSEM** + **bộ lọc Kalman** cho dữ liệu Toán THPT từ
> hệ thống OLM (Việt Nam), năm học 2024–2025. Bài báo NCKH viết bằng tiếng Việt theo
> format **HNUE Journal of Science** đính kèm trong `paper/`.

## Cài đặt

```bash
# Python (preprocessing)
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt   # hoặc `uv sync` nếu dùng uv

# R packages (chính)
Rscript -e 'install.packages(c("mirt", "lavaan", "lme4", "ctsem", "KFAS", "rmarkdown", "bit64"))'
```

## Chạy pipeline

```bash
bash run_pipeline.sh
```

| Bước | Tool | Vai trò | Output chính |
|------|------|---------|--------------|
| B0 | Python | Tiền xử lý + tạo response_long | `response_long_*.csv`, `day_mapping_*.csv` (riêng tư) |
| B1 | R | Kiểm tra một chiều (EFA + scree) | `scree_plot_*.png` |
| B2 | R | Hiệu chuẩn IRT 1PL (`mirt`) | `irt_1pl_grade_*.csv` (item bank, công khai) |
| B3 | R | Chấm điểm EAP | `theta_trajectory_*.csv` (riêng tư) |
| B4a | R | LGCM/LCSM (lavaan) + lmer | `lgcm_params_*.csv`, `lcsm_params_*.csv`, `mlm_*.rds` |
| B4c | R | CT-DSEM khối 12 (ctsem) | `ctdsem_population_params.csv` |
| B5 | R | Hợp nhất + render báo cáo | `b5_report.html`, `final_*.csv` |
| B6 | R | Kalman smoothing (KFAS) | `kalman_pop_metrics.csv` + per-student (riêng tư) |
| B7 | R | Cảnh báo sớm + gợi ý câu hỏi | `early_warning_*.csv`, `recommendation_*.csv` (riêng tư) |

## Bài báo

Source LaTeX ở [`paper/`](paper/). Build:

```bash
cd paper && make pdf
```

Yêu cầu: TeX Live đầy đủ hoặc TinyTeX với `setspace, titlesec, caption, multicol, tikz, cite,
hyperref, fancyhdr, vntex, babel-vietnamese, enumitem, ieeetran`. Xem chi tiết ở `paper/README.md`.

## Phân loại file: công khai ↔ riêng tư

Repo lưu **mã nguồn** và **các artefact tổng hợp**. Bất kỳ tệp nào chứa định danh học sinh
(`iduser`) hoặc bản ghi đáp ứng từng câu (`question_id × iduser`) đều **không** được commit
(bảo vệ qua `.gitignore`).

| Thành phần | Trạng thái | Ghi chú |
|---|---|---|
| `src/` | **Công khai** | Source code Python + R (B0–B7) |
| `docs/` | **Công khai** | Tài liệu nghiên cứu — không chứa PII |
| `paper/` | **Công khai** | LaTeX bài báo + figures + bib (ảnh đã ẩn danh) |
| `run_pipeline.sh`, `requirements.txt`, `pyproject.toml` | **Công khai** | Pipeline + dependency manifest |
| `outputs/b5_report/final_*.csv` + `fig_*.png` + `b5_report.html` | **Công khai** | Kết quả tổng hợp, không chứa PII |
| `outputs/b2_calibration/irt_*pl_grade_*.csv` + `plots/` | **Công khai** | Item bank: `question_id → b` |
| `outputs/b4_lsem/{lgcm,lcsm,mlm}_params_grade_*.csv` + `plots/` | **Công khai** | Tham số tổng hợp per-grade |
| `outputs/b6_kalman/kalman_pop_metrics.csv` + `plots/` | **Công khai** | Aggregate metrics + plot ẩn danh ("HS 1–9") |
| `outputs/b1_dimensionality/scree_plot_*.png` + `b1_decision.txt` | **Công khai** | EFA result, không PII |
| `outputs/b{0,3}/response_long_*.csv`, `theta_trajectory_*.csv` | **Riêng tư** | Per-student, chứa `iduser` |
| `outputs/b3_theta/plots/trajectory_samples_*.png` | **Riêng tư** | Hiển thị `iduser` thật ở panel labels |
| `outputs/b{6,7}/*_grade_*.csv` (kalman_smoothed, early_warning, recommendation_demo) | **Riêng tư** | Per-student outputs |
| `outputs/b4_lsem/ctdsem_individual_*.csv`, `ctdsem_predicted_trajectories.csv` | **Riêng tư** | Per-student CT-DSEM |
| `*.rds` (b1, b2, b4 model objects) | **Riêng tư** | Nhúng dữ liệu thô — tái fit được từ code |
| `data/`, `.env`, `.venv/`, `*.log` | **Riêng tư** | Dữ liệu thô, secrets, build artefacts |

## Tái lập

Để chạy lại pipeline từ đầu cần dữ liệu thô (`response_long_*.csv` từ OLM Math).
Dữ liệu này không công khai vì lý do bảo mật học sinh; nhà nghiên cứu cần truy cập cho mục
đích tái lập có thể liên hệ tác giả.

Các CSV trong `outputs/b5_report/` đã đủ để tái sinh **toàn bộ bảng và hình trong bài báo**.
Hai script: `src/r/b5_consolidate.R` (tổng hợp) và `src/r/b5_report.Rmd` (render báo cáo).

## Trích dẫn

```bibtex
@article{nguyen2026irtlsem,
  title  = {Real-time estimation of student ability based on Item Response Theory (IRT)
            and Longitudinal Structural Equation Modeling (LSEM)},
  author = {Nguyễn, Tiến Đạt and Nguyễn, Diệp Linh and Bạch, Đức Anh and
            Bùi, Thị Thu Thuỷ and Phạm, Lê Nhật Linh},
  journal= {HNUE Journal of Science},
  year   = {2026},
  note   = {Submitted}
}
```

## Liên hệ

- **Corresponding author:** Nguyễn Tiến Đạt — `mas835151465@hnue.edu.vn` (chính), `datlcpro@gmail.com` (phụ)
- **Người hướng dẫn chính:** PGS.TS. Phạm Thọ Hoàn
- **Đơn vị:** Khoa Công nghệ Thông tin, Trường Toán học và Công nghệ thông tin, Trường Đại học Sư phạm Hà Nội

## Giấy phép

- **Code** (mã nguồn `src/`, scripts, paper LaTeX source): **MIT** — xem [`LICENSE`](LICENSE).
- **Bài báo** (`paper/*.pdf` text + figures): **CC-BY-4.0**.
