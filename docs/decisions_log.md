# Decisions Log

## 2026-05-25: Calibration scope

**Decision:** Per-grade calibration (3 thang θ độc lập)

**Reason:** Phân tích anchor items cho thấy:
- 10↔11: 4 items (bất khả thi)
- 10↔12: 44 items (yếu)
- 11↔12: 338 items (đủ nhưng chưa cần)
- Cả 3 lớp: 0 items

→ Không vertical scaling trong Phase 1. Mỗi lớp calibrate riêng.

## 2026-05-25: Data scope

**Decision:** Chỉ năm 2024-2025

**Reason:** Data đã đầy đủ (07/2024 – 06/2025). Phase 2 sẽ mở rộng thêm 2025-2026 khi có khóa ôn tập THPT (anchor items tự nhiên cho vertical scaling).

## 2026-05-25: Tool stack

**Decision:** Python (uv) cho B0, R (renv) cho B1-B4

**Reason:** 
- Python nhanh hơn 5-10× cho preprocessing 7M rows
- R (mirt, lavaan, ctsem) là gold standard cho psychometric + SEM
- Giao tiếp qua CSV — debuggable, standalone

## 2026-05-25: B1 Dimensionality result

**Result:**
- Grade 10: ECV = 0.556 (ev1/ev2 = 2.75)
- Grade 11: ECV = 0.578 (ev1/ev2 = 3.34)
- Grade 12: ECV = 0.679 (ev1/ev2 = 6.04)

**Decision:** Giữ nguyên 1D (1PL + 2PL) cho B2.

**Reason:**
- Khung mô hình chưa có hướng xử lý MIRT 2D
- ECV tính trên sparse matrix (65-79%) → kết quả có thể bị inflate bởi testlet/block artifact
- Ghi nhận như limitation trong bài báo
- RI-CLPM (Kiểu 3) để explore sau nếu cần

## 2026-05-26: B2 → B3 — Quyết định dùng 1PL cho cả 3 grades

### Bối cảnh
Sau khi B2 hoàn tất cả 3 grades:
- 1PL: clean cho cả 3 (0% items extreme |b|>6, 0.4-1.3% có |b|>4)
- 2PL: 2-6% items "degenerate" (a<0, |b| extreme)
  - Grade 10: 22/958 (2.3%)
  - Grade 11: 47/749 (6.3%)
  - Grade 12: 98/2199 (4.5%)
- Itemfit S-X2 failed do data sparse (mỗi HS chỉ làm <10% items)

### Quyết định: Dùng 1PL (Rasch) cho B3 — cả 3 grades

### Lý do
1. **Methodological consistency**: cả 3 grades cùng model, dễ so sánh dynamics
2. **Tránh items degenerate**: 1PL không có vấn đề a<0 (a fixed = 1)
3. **Robust với data sparse**: 1PL chỉ cần estimate 1 param/item, ít data hơn vẫn OK
4. **Đủ cho LSEM**: θ trajectory chính là input cho LGCM/LCSM/CT-DSEM, không cần 2PL precision
5. **Standard practice**: nhiều LSEM papers dùng Rasch làm measurement model

### 2PL giữ làm gì
- Sensitivity analysis trong bài báo: "Kết quả robust với choice of IRT model"
- Phụ lục: so sánh θ_1PL vs θ_2PL (correlation expected > 0.95)
- Reviewer-friendly: defending 1PL choice với evidence của 2PL

### Hệ quả cho pipeline
- B3 chỉ chạy fscores với 1PL mirt objects
- Output: `theta_trajectory_1pl_grade_{N}.csv`
- 2PL fscores có thể compute sau (parallel run, không blocking)

## 2026-05-27: B3 EAP Scoring — HOÀN THÀNH

### Cấu hình
- Model: 1PL Rasch (theo quyết định 2026-05-26)
- Method: EAP với prior N(0, 1)
- Implementation: `mirt::fscores(method="EAP", response.pattern=...)`, batch 500 HS/lần
- Per (HS, day): build response vector aligned to calibrated items, fill 0/1 hoặc NA

### Kết quả

| Grade | n measurements | n HS | θ mean | θ sd | θ range | SE median |
|-------|---------------|------|--------|------|---------|-----------|
| 10 | 32,191 | 6,407 | 0.058 | 0.914 | [-4.06, 2.71] | 0.492 |
| 11 | 29,959 | 7,002 | 0.057 | 1.077 | [-5.08, 3.27] | 0.507 |
| 12 | 60,807 | 10,804 | 0.051 | 1.052 | [-4.83, 3.27] | 0.421 |

### Đánh giá
- ✅ θ mean ~ 0, sd ~ 1: chính xác như expected với EAP prior N(0,1)
- ✅ Range [-5.1, 3.3]: trong vùng hợp lý của ability
- ✅ SE median 0.42-0.51: reasonable cho ~22 items median per measurement
- ✅ Slight shrinkage to mean (sd < 1): bình thường với EAP

### Output files
- `outputs/b3_theta/theta_trajectory_1pl_grade_{10,11,12}.csv`
- Columns: `iduser, day_idx, date, n_items, theta, se`

### Thời gian thực thi
- Total ~20 phút trên local machine (3 grades, batched)

### Bước tiếp theo
- B4a: LGCM + LCSM trên cả 3 grades (lavaan)
- B4c: CT-DSEM grade 12 only (ctsem)
- 2PL EAP scoring có thể chạy sau như sensitivity analysis

## 2026-05-27: B4 (LSEM) — HOÀN THÀNH

### B4a: LGCM + LCSM + lmer (3 grades)

**Tier 1 — LGCM/LCSM (lavaan, max_T=4, bootstrap CI 1000):**

| Model | Grade | CFI | RMSEA | SRMR | Slope/b | 95% CI |
|-------|-------|-----|-------|------|---------|--------|
| LGCM  | 10    | .996 | .019 | .011 | 0.015 | [.004, .023] |
| LGCM  | 11    | .991 | .031 | .017 | 0.028 | [.017, .039] |
| LGCM  | 12    | .997 | .023 | .011 | 0.006 | [-.002, .013] |
| LCSM  | 10    | .998 | .020 | .008 | b=-0.069 | [-.119, -.022] |
| LCSM  | 11    | .999 | .019 | .007 | b=-0.043 | [-.091, .010] |
| LCSM  | 12    | .998 | .025 | .010 | b=+0.002 | [-.026, .030] |

**Tier 2 — lmer (no cap, precision weights):**
- Grade 10: slope=0.003 (SE=0.002)
- Grade 11: slope=0.009 (SE=0.003)
- Grade 12: slope=0.001 (SE=0.001)

**Convergent evidence**: |LGCM - lmer| > 0.005 cho tất cả grades. Diễn giải: khác biệt CHỦ YẾU do **method** (FIML imputation vs REML), không phải nonlinearity. lmer-capped (T≥4 subset, cap t<4) cũng khác LGCM ~0.006-0.011 → confirm method effect.

**Bootstrap warnings**: Grade 10 LGCM 68.6%, grade 12 LGCM 84.9% nonadmissible — Heywood cases trong resampling do data sparse. Bootstrap CI cho LGCM grade 12 không hoàn toàn tin được; primary inference dùng lmer Tier 2.

### B4c: CT-DSEM grade 12 (mode=optim, MAP estimates)

**Subsample**: 460 HS với T≥15 measurements, 9,591 observations, time range 0-207 days.

**Population params:**
- mean_T0 = -0.049 [-0.125, 0.026]
- var_T0 = 0.760 [.707, .816]
- phi (drift) = -0.0017 [-.0027, -.0010]
- cint (intercept) = 0.0011 [.0006, .0016]
- sigma (diffusion) = 0.046 [.041, .053]
- manifest_var = 0.572 [.562, .582]

**Derived insights:**
- Equilibrium θ ≈ -cint/phi = 0.65 logit (asymptotic ability level)
- Half-life ≈ 408 days (~1.1 năm) → dynamics rất chậm, learning đòi hỏi thời gian
- Individual heterogeneity: 920 ind params (phi_i + cint_i for each HS)

### Output files
```
outputs/b4_lsem/
├── lgcm_grade_{10,11,12}.rds
├── lcsm_grade_{10,11,12}.rds
├── mlm_grade_{10,11,12}.rds
├── lgcm_params_grade_{10,11,12}.csv
├── lcsm_params_grade_{10,11,12}.csv
├── mlm_params_grade_{10,11,12}.csv
├── b4a_fit_indices.csv
├── b4a_slope_lgcm_vs_mlm.csv
├── ctdsem_grade_12.rds
├── ctdsem_individual_params.csv
└── ctdsem_summary.txt
```

### Bước tiếp theo
- B5: Report + visualization (R Markdown + matplotlib)
- (Optional) Chạy CT-DSEM MCMC mode để có full Bayesian CI
- (Optional) Sensitivity analysis với 2PL EAP scoring

## 2026-05-27: B4c per-day stats + visualization — HOÀN THÀNH

### Bổ sung outputs từ b4c_ctdsem.R

- `ctdsem_individual_rates.csv` — per-HS wide format với derived metrics:
  - `theta_eq_i = -cint_i / phi_i` (asymptotic ability per HS)
  - `half_life_days_i = ln(2) / |phi_i|`
  - `rate_at_theta_{neg1, 0, pos1}` — expected dθ/dt tại θ = -1, 0, +1
- `ctdsem_predicted_trajectories.csv` — 1-year trajectory predictions cho θ_0 ∈ {-1.5, -0.5, 0, 0.5, 1.5}

### Visualizations (b4c_viz.R) — 5 plots

| File | Mô tả |
|------|-------|
| `ctdsem_phi_distribution.png` | Distribution of φ_i (mean-reversion rate) |
| `ctdsem_cint_distribution.png` | Distribution of c_i (continuous intercept) |
| `ctdsem_theta_eq_distribution.png` | Distribution of θ_eq_i (per-HS asymptote) |
| `ctdsem_predicted_trajectories.png` | 1-year trajectories từ 5 initial θ levels |
| `ctdsem_rate_vs_theta.png` | dθ/dt vs current θ — catch-up vs Matthew per HS |

### Per-day interpretation (FAQ cho bài báo)

**"408 ngày" KHÔNG phải period analysis** — đó là half-life của population mean dynamics:
- Half-life = ln(2)/|φ| ≈ 408 days (slow learning curve)
- Time range thực tế của data: 0-207 days

**dθ/dt tính theo NGÀY:**
- φ = -0.0017 logit/day (population mean)
- cint = 0.0011 logit/day
- Equilibrium θ_eq = -cint/φ ≈ 0.65 logit

**Predicted change for typical HS:**
| Hiện tại | dθ/dt | 1 tuần | 1 tháng | 1 học kỳ (90d) |
|----------|-------|--------|---------|----------------|
| θ = -1.0 | +0.0028 | +0.020 | +0.084 | +0.252 |
| θ = 0.0  | +0.0011 | +0.008 | +0.033 | +0.099 |
| θ = +1.0 | -0.0006 | -0.004 | -0.018 | -0.054 |

→ **Catch-up effect continuous-time**: HS yếu cải thiện ~0.25 logit/học kỳ, HS giỏi regression to mean nhẹ.

### Pipeline status check

| Step | Status | Notes |
|------|--------|-------|
| B0 Preprocess | ✅ | 3 grades |
| B1 Dimensionality | ✅ | 1D OK with caveat (sparse data) |
| B2 IRT 1PL/2PL | ✅ | 1PL clean; 2PL has 2-6% degenerate items |
| B2 Postprocess | ✅ | Clean items + X2/infit fallback |
| B3 EAP scoring | ✅ | 1PL only per decision |
| B4a LGCM/LCSM/lmer | ✅ | 3 grades, fit excellent (CFI>.99) |
| B4c CT-DSEM grade 12 | ✅ | optim mode, 460 HS, 5 plots |

### Open caveats (sẽ document trong bài báo, không block B5)

1. **Itemfit S-X2** failed do data sparse → dùng X2/infit (alternative chi-square)
2. **B4a bootstrap nonadmissible** 68-85% cho LGCM grade 10/12 → primary inference từ lmer Tier 2
3. **B4a convergent threshold 0.005** không đạt → diễn giải là method effect (FIML vs REML)
4. **2PL EAP** chưa chạy — sensitivity analysis tương lai
5. **CT-DSEM MCMC** chưa chạy — dùng MAP estimates (optim mode) cho point estimates + Wald CI; full Bayesian tương lai

### Sẵn sàng B5

Tất cả inputs cho report đều đã có. B5 sẽ tổng hợp:
- Bảng tham số chính (LGCM slope, LCSM b, CT-DSEM phi/cint) cross-grade
- Visualizations key (LGCM trajectories, CT-DSEM predictions, individual heterogeneity)
- Cross-method convergent evidence table
- Methodology section + caveats

## 2026-05-27: B5 (Final Report) — HOÀN THÀNH

### Scripts
- `src/r/b5_consolidate.R` — gộp params từ tất cả B4 outputs thành tables ngắn gọn
- `src/r/b5_report.Rmd` — R Markdown render → `outputs/b5_report/b5_report.html` (1.7MB self-contained)
- `src/r/b5_verify_final.R` — replication check, exit code 0 nếu pass

### Output structure
```
outputs/b5_report/
├── final_fit_indices.csv             # 6 rows (3 grades × 2 models)
├── final_lgcm_params.csv             # 12 rows (3 × 4 params)
├── final_lgcm_params_pretty.csv      # for paper tables
├── final_lcsm_params.csv             # 9 rows (3 × 3 params)
├── final_lcsm_params_pretty.csv
├── final_mlm_params.csv              # 18 rows (3 × 6 params)
├── final_convergent_evidence.csv     # LGCM vs lmer per grade
├── final_ctdsem_population.csv       # 6 params, grade 12
├── final_ctdsem_individual_summary.csv  # 4 metrics × 3 stats
├── final_summary.txt                 # text summary for terminal
└── b5_report.html                    # full self-contained report
```

### Verify final results

✓ All output files present
✓ All CFI > 0.95 (excellent fit)
✓ All RMSEA < 0.06
✓ All SRMR < 0.08
✓ All LGCM slopes positive (consistent direction across grades)
✓ LCSM catch-up confirmed for grade 10 (b=-0.069, CI excludes 0)
✓ lmer non-negative variances (no Heywood)
✓ CT-DSEM phi negative (mean-reverting, stable dynamics)
✓ CT-DSEM equilibrium plausible (~0.65 logit)
⚠ 3/3 grades fail convergent threshold |Δslope|<0.005 → method effect, documented

Cross-grade slope CV = 0.69 (high relative variation due to small magnitudes; direction consistent).

### Pipeline FINAL status

| Step | Status | Output |
|------|--------|--------|
| B0 | ✅ | response_long, day_mapping (3 grades) |
| B1 | ✅ | bifactor + ECV → 1D adopted |
| B2 | ✅ | 1PL + 2PL params (1PL primary) |
| B2 postproc | ✅ | clean items |
| B3 | ✅ | EAP θ trajectories |
| B4a | ✅ | LGCM, LCSM, lmer (3 grades) + sensitivity |
| B4c | ✅ | CT-DSEM grade 12 + per-day rates + 5 plots |
| B5 | ✅ | consolidate + Rmd report + verify |

**All steps complete. Pipeline reproducible end-to-end. Ready for paper writing.**

## 2026-05-27: B5 — bổ sung figures + narrative (paper-ready)

### Bối cảnh
B5 phiên bản đầu mới có consolidate tables + Rmd dạng technical report + verify.
Còn thiếu so với spec `docs/plan_thuc_hien.md` (mục B5): 4 hình chính cho bài báo,
bảng so sánh slope 3 method, và các mục narrative (Introduction/Discussion/Conclusion).
Bổ sung lần này **chỉ thêm/mở rộng**, không sửa số liệu hay logic đã có.

### Artifact mới
- `src/r/b5_plots.R` (mới) — sinh 4 hình + composite:
  - `fig_lgcm_trajectories.png` — quỹ đạo tăng trưởng population 3 grade
  - `fig_lcsm_coupling.png` — coupling b: catch-up→plateau (KEY FINDING)
  - `fig_slope_comparison.png` — LGCM / MLM-weighted / MLM-unweighted × grade
  - `fig_dtheta_vs_theta.png` — dθ/dt vs θ (CT-DSEM grade 12), đọc phi/cint từ CSV
  - `fig_main_results.png` — composite 2×2 (dpi 300) cho bài báo
- `final_slope_comparison.csv` (mới) — append block trong `b5_consolidate.R`.
  MLM-unweighted được **refit REML không weights** từ `b3_theta` (read-only on b3).
- `b5_report.Rmd` — thêm mục Introduction (RQ1–3), Main Results Figure, Discussion
  (compensatory→plateau, pedagogical, methodological 3-tier, lit), Conclusion;
  đổi "Cross-grade Replication" → "Cross-grade Pattern" (reframe threshold);
  bật MathJax + viết công thức mô hình bằng LaTeX (render trong HTML).
- `b5_verify_final.R` — thêm check `final_slope_comparison.csv` (9 rows),
  `fig_main_results.png`, và các mục Introduction/Discussion/Conclusion + key finding.
- `run_pipeline.sh` — block B5 nay chạy đủ: consolidate → b4c_viz → b5_plots → render → verify.

### Số liệu giữ nguyên
Không thay đổi bất kỳ giá trị nào trong các entry trước; slope_comparison chỉ tổng hợp
lại từ outputs B4 + 1 lần refit lmer không weights (point estimate, không ảnh hưởng B4).

## 2026-05-27: B5 giai đoạn 2 — diagnostic charts + reliability + baseline

### Bối cảnh
Sau giai đoạn 1, bổ sung thêm theo yêu cầu: (a) đầy đủ biểu đồ chẩn đoán B0–B4,
(b) lấp 2 khoảng trống số liệu của khung — reliability (8.3) và so sánh baseline tĩnh
vs động (8.4). KHÔNG chạy 2PL EAP / LGCM bậc 2 / LCSM dual (để Phase sau).

### Script viz mới (đọc outputs có sẵn → `outputs/b{N}/.../plots/`)
- `src/r/b0_plots.R` — histogram $T_i$ + phân phối $\Delta t$ (day-level, log scale), 3 grade.
- `src/r/b2_plots.R` — phân phối $b$ (1PL vs 2PL), phân phối $a$ (2PL), Wright map,
  ICC 9 câu đại diện (tính giải tích $P=\sigma(a(\theta-b))$, không cần mirt rds).
- `src/r/b3_plots.R` — 9 HS mẫu (±SE), phân phối $\hat\theta$, phân phối SE.
- `src/r/b4a_viz.R` — LGCM overlay (population vs 50 HS), LCSM $\Delta\theta$ density theo
  tercile $\theta_0$ (trực quan catch-up). (scree B1 đã có sẵn → chỉ nhúng.)

### Số liệu mới (append vào `b5_consolidate.R`)
- `final_reliability.csv` — $\rho_{\hat\theta}=1-\overline{SE^2}/\widehat{Var}(\hat\theta)$:
  **G10=0.69, G11=0.75, G12=0.81** (G10 hơi dưới ngưỡng 0.70 — ghi nhận, do test ngắn/ít tin hơn).
- `final_baseline_comparison.csv` — static (random-intercept, θ hằng số trong năm; proxy
  cho Rasch tĩnh OLM) vs dynamic (intercept+slope), ML cho LRT. **Dynamic thắng tuyệt đối
  mọi grade** (ΔAIC ≈ 82/92/167; LRT p ≈ 1e-19…1e-37).

### Nhúng report + verify
- `b5_report.Rmd`: thêm §3.2 (B2 plots), §3.3 Data shape & dimensionality (B0+scree),
  §3.4 Measurement quality (B3 plots + bảng reliability), plot LGCM/LCSM ở §5.2/§5.3,
  §6.4 Value added over a static baseline (bảng baseline). MathJax + LaTeX giữ nguyên.
  HTML render OK (3.9MB, 28 ảnh nhúng base64).
- `b5_verify_final.R`: thêm check 2 CSV mới + 8 plot đại diện + ρ∈(0,1) + LRT p<.05.
  **Kết quả: ALL CHECKS PASSED (41/41).**
- `run_pipeline.sh`: block B5 chạy thêm b0/b2/b3/b4a viz trước render.

### Vẫn còn để Phase sau (không làm lần này, đã thống nhất)
2PL EAP sensitivity (1PL vs 2PL), LGCM bậc 2 + LCSM dual, CT-DSEM group-level, RI-CLPM.

## 2026-05-28: Phase 1 scope refinement — B6 (Kalman) + B7 (Applications), defer 8.3 + RI-CLPM + teacher analysis

**Context.** Đối chiếu đề cương `docs/nckh/de_cuong/De_cuong_nghien_cuu_IRT_LSEM.docx` với báo cáo Phase 1 hiện có (B0–B5, verify 41/41), phát hiện 3 khoảng trống lớn: MT2 (Kalman + VI/OIRT) chưa chạm, MT4 (3 ứng dụng) chỉ làm tượng trưng, 8.3 (production code) chưa có. Quyết định scope refinement có cơ sở phương pháp luận thay vì cố làm cho đủ.

**ADD (đã làm):**
- **B6 Kalman Smoother** (`src/r/b6_kalman.R`) — local-level state-space per HS, time-varying H_t = SE²_t từ B3, pooled q_g per grade qua method of moments. KFAS package (auto-install pattern y như b4c_ctdsem.R:27-40). Outputs: `outputs/b6_kalman/kalman_smoothed_grade_{N}.csv` + `kalman_pop_metrics.csv` + plots. **Đóng MT2(a).**
- **B7a Early-warning** (`src/r/b7a_early_warning.R`) — flag HS với slope (từ ranef của mlm_grade_{N}.rds) bottom-10% HOẶC max(Δθ) < −0.5. Output: `early_warning_grade_{N}.csv` với cờ OR + AND + flag_reason 4-set. **Đóng MT4(a).**
- **B7b Item recommendation** (`src/r/b7b_recommendation.R`) — hàm `recommend_items()` chọn top-k items với |b−θ| nhỏ nhất (1PL info-max, δ=0.5). Demo 10 HS/grade (3 low + 4 mid + 3 high). **Đóng MT4(b).**
- **VI/OIRT design doc** (`docs/oirt_vi_design.md`) — ELBO derivation (Jaakkola hoặc reparameterisation), streaming update pseudocode, complexity analysis, kết nối với B6 Kalman (Kalman = closed-form Gaussian special case). **Đóng MT2(b) ở mức theoretical contribution.**
- **`docs/scope_refinement.md`** — bảng 3-cột đề cương ↔ delivery ↔ status + reason, minh bạch toàn bộ điểm lệch để reviewer đối chiếu.
- **b5_report.Rmd**: chèn **§8 Kalman smoothing (B6)** + **§9 Applications (B7)** đúng thứ tự sau §7 CT-DSEM. Downstream renumbered: Cross-grade §8→§10, Discussion §9→§11 (subsections §11.1-11.4), Limitations §10→§12, Conclusion §11→§13, Reproducibility §12→§14. §12 bổ sung 3 bullet (no teacher metadata, RI-CLPM single-construct, VI/OIRT design-only). §11.3 cập nhật "3-tier → multi-tier convergent design" để gộp Kalman. §13 thêm 1 đoạn về B6+B7 deliverables.
- **b5_consolidate.R**: thêm Block 6b (`final_kalman_gain.csv`) + 6c (`final_early_warning_summary.csv` + `final_recommendation_examples.csv`).
- **b5_verify_final.R**: thêm checks §13-§16 (Kalman gain in (0,1), early-warning n_flagged>=1 + pct<=25%, ≥30 unique HS demo, keywords "Kalman" + "Applications" trong HTML).
- **run_pipeline.sh**: render 1 lần duy nhất ở cuối (B5 chỉ sinh CSV+plot, B6+B7 chạy độc lập, rồi b5_consolidate re-run + render + verify).

**DROP có cơ sở phương pháp luận:**
- **RI-CLPM** — single-construct Phase 1 (chỉ math θ) → RI-CLPM thiết kế cho ≥2 construct chéo-trễ → degenerate thành AR(1), không thêm thông tin so với CT-DSEM. Phase 2 mở RI-CLPM khi có construct thứ 2 (engagement / second-subject).
- **DSEM (discrete)** → **CT-DSEM (Ornstein-Uhlenbeck)** đã làm B4c là **upgrade**, không substitution. OLM Δt bất đều 5 bậc → discrete DSEM misspecified ngay từ giả thiết.

**DEFER có lý do cứng (không phải "không kịp"):**
- **MT4(c) teaching effectiveness** — verified schema-level rằng OLM math không có `class_id`/`teacher_id`/`school_id` (kiểm tra `math_teacher_static/_categories/_course`, `DATA_STRUCTURE.md §2.1`, B0 outputs, B0 preprocess script, grep toàn codebase). Phase 2 cần ETL bổ sung từ collection khác.
- **Dataset 2 (trường THPT)** — cần partnership + IRB-equivalent + 1 học kỳ admin window. Phase 2 (năm học 2026-2027).
- **8.3 Production code** — production engineering khác research deliverable. B6 R code là reference implementation; Phase 2 team OLM sẽ reimplement theo platform constraints.
- **VI/OIRT runtime** — cần streaming infra. Design doc xong, runtime Phase 2.

**Không sửa số liệu cũ.** B0-B4 outputs nguyên vẹn; B5 baseline (LGCM/LCSM/lmer/CT-DSEM/reliability/baseline LRT) số liệu y cũ; chỉ thêm B6+B7 layers + 2 chương mới trong report (§8, §9), renumber các chương sau xuống tương ứng.

**B7a parameter refinement trong lúc chạy** (đã ghi log + giải thích trong §9.1 của report):
- Drop threshold từ -0.5 → **-1.0 logit** và signal lấy từ **Kalman-smoothed θ** (B6 output) thay vì raw EAP. Lý do: SE_raw ≈ 0.5 logit → threshold -0.5 ≈ 1 SE → 70% false-flag. SE_smooth ≈ 0.4 logit + threshold -1.0 ≈ 2.5 SE → flag rate hợp lý 14-22% (G10<G11<G12, phù hợp catch-up→plateau).
- `iduser` int64 (giá trị ~1.7e13 vượt range integer 32-bit) → dùng `bit64::as.integer64()` khi round-trip qua rownames.
