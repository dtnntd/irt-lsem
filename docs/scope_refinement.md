# Scope Refinement — đề cương ↔ Phase 1 delivery

**Date:** 2026-05-28
**Status:** authoritative mapping of the original NCKH proposal (`docs/nckh/de_cuong/De_cuong_nghien_cuu_IRT_LSEM.docx`) against what Phase 1 actually delivered, with reasons for each deviation.

This document exists so that any reviewer reading the proposal and the Phase 1 report side by side can see exactly **what changed and why** — not because items were skipped, but because the data and methodology produced informed scope decisions.

## 1. Mục tiêu ↔ delivery map

| Đề cương MT | Phase 1 deliverable | Status | Reason |
|---|---|---|---|
| **MT1.** Integrate IRT into LSEM (LGCM, LCSM, RI-CLPM, DSEM) | B2 (1PL calibration), B3 (EAP scoring), B4a (LGCM + LCSM + lmer), B4c (CT-DSEM grade 12) | **PARTIAL (3/4)** | LGCM, LCSM, DSEM (as CT-DSEM) ✓. RI-CLPM dropped — see §2.1. |
| **MT2(a).** Real-time estimation via Kalman + recursive update | B6 Kalman Smoother (`src/r/b6_kalman.R`, KFAS local-level with time-varying H from B3 SE) | **DELIVERED** | Added in this scope refinement to close the proposal's biggest gap. |
| **MT2(b).** Variational Inference for streaming OIRT | `docs/oirt_vi_design.md` — full ELBO derivation, update pseudocode, complexity analysis | **REFRAMED** | Runtime deferred to Phase 2 (needs streaming infra). The algorithmic specification *is* the research contribution; an unimplemented runtime is not. |
| **MT3.** Validation on OLM data + comparison against static Rasch baseline | B0–B5 entire pipeline; §6.4 of report (static-vs-dynamic LRT, ΔAIC 82/92/167, $p \approx 10^{-19}\!\dots\!10^{-37}$) | **DELIVERED** (OLM) / **DEFERRED** (school dataset) | OLM data fully analysed. The proposal's second dataset (đánh giá định kỳ STEM ở trường) requires school partnership and IRB-equivalent process — see §2.4. |
| **MT4(a).** Phát hiện sớm HS giảm năng lực | B7a early-warning (`src/r/b7a_early_warning.R`) — bottom-10% slope ∪ Δθ<−0.5 | **DELIVERED** | Added in this scope refinement. |
| **MT4(b).** Cá nhân hoá lộ trình học | B7b 1PL information-max recommender (`src/r/b7b_recommendation.R`) | **DELIVERED** | Added in this scope refinement. |
| **MT4(c).** Đánh giá hiệu quả giảng dạy theo tốc độ tăng trưởng | — | **DEFERRED** | OLM math schema has no class/teacher/school field — see §2.3. |
| **8.1.** Sản phẩm khoa học (WoS/Scopus/quốc tế/trong nước) | Paper outline in `docs/paper_outline.md` (Phase 2 work) | **NOT YET** | Outside Phase 1 deliverable window. |
| **8.3.** Bộ mã production tích hợp Kalman + Bayes có thể nhúng OLM | — | **DEFERRED** | Production engineering is out of scope for a research deliverable; B6 R code is a clean reference implementation that a Phase 2 engineering effort can reimplement against the OLM platform. |

## 2. Specific deviations explained

### 2.1 RI-CLPM dropped (single-construct → over-specified)

The proposal lists Random-Intercept Cross-Lagged Panel Model among four LSEM variants. RI-CLPM was developed by Hamaker et al. (2015) to separate **trait-like between-person variance** from **within-person fluctuation** in a system of **two or more** longitudinally measured constructs (e.g. ability × motivation, X cross-lagged with Y).

Phase 1 measures a single construct — mathematics ability $\theta$. With one variable, RI-CLPM reduces algebraically to a random-intercept AR(1) which is exactly what CT-DSEM (or its discrete cousin) already provides. Forcing a single-construct RI-CLPM would not be wrong but would add no information.

**Methodological rationale, not a time decision.** A second longitudinal construct (e.g. engagement metrics, or a second-domain $\theta$) would justify RI-CLPM and is a clear Phase 2 candidate.

### 2.2 DSEM → CT-DSEM (Ornstein–Uhlenbeck) — *upgrade*, not substitution

The proposal writes DSEM in its discrete form
$\theta_{it} = \varphi_i \theta_{i,t-1} + X_{it}^\top \beta_i + \omega_{it}$,
which assumes a fixed $\Delta t$. OLM inter-occasion gaps span five orders of magnitude (minutes to months), so discrete DSEM is misspecified at the time-axis level.

CT-DSEM (Driver, Oud & Voelkle 2017; Asparouhov, Hamaker & Muthén 2018) is the **continuous-time generalisation**: the Ornstein–Uhlenbeck stochastic differential equation
$d\theta_{it} = (\mu_i - \varphi_i \theta_{it})\,dt + \sigma_i\,dW_t$
collapses to discrete DSEM as a special case when $\Delta t$ is constant, and remains identified when it is not.

This is therefore an **upgrade dictated by data characteristics**, not a substitution. The discrete-DSEM exogenous-covariate term $X^\top \beta$ is omitted because Phase 1 has no time-varying covariates available; adding them is Phase 2 work.

### 2.3 MT4(c) teaching-effectiveness deferred — schema-level evidence

Verified against:

- `app/objects/` user/log object schemas
- `database/Database.py` collection references
- B0 preprocess script `src/python/b0_preprocess.py`
- B0 outputs (`response_long_*.csv`, `day_mapping_*.csv` — both lack any class/teacher field)
- `docs/DATA_STRUCTURE.md` §2.1 schema for `math_teacher_static`
- grep across the codebase for `class_id`, `teacher_id`, `school_id`, `classroom`, `enrollment`

Result: **no class, teacher, or school identifier exists in the data the IRT-LSEM pipeline currently sees, nor in the upstream OLM math collections** (`math_teacher_static`, `math_teacher_categories`, `math_teacher_course`).

Doing class-level / teacher-level growth analysis requires:

1. Locating the relevant collection in the live OLM MongoDB (likely under a non-`math_teacher_*` namespace),
2. Extending the Phase A/B extraction pipeline to pull `(iduser, class_id, teacher_id)`,
3. Updating B0 to propagate these IDs,
4. Adding a multi-level nesting layer to B4a (`(1 + day_idx | class_id/iduser)`).

This is a multi-week ETL+modelling project, properly Phase 2.

### 2.4 Dataset 2 (school-based) deferred — needs partnership

The proposal lists two datasets: OLM and "đánh giá định kỳ và thường xuyên các môn STEM" from schools. Phase 1 used OLM only. School-based assessment data requires:

- A formal partnership with 2–3 THPT schools,
- Approval for collecting student response data,
- A test administration window of at least one semester.

None of these fits the Phase 1 timeline. The Phase 2 plan is to negotiate with partner schools during the 2026–2027 school year and run the same IRT-LSEM pipeline on the new corpus as a generalisation check.

### 2.5 Production code (8.3) deferred

A research deliverable is not the same as a production-ready service. The B6 R implementation is a *reference* — readable, reproducible, and verifiable — but reimplementing it as a service that hooks into the OLM platform requires platform-side engineering decisions (transport, serialisation, recalibration policy, observability) that belong to the OLM team's engineering roadmap, not to this research project.

The `docs/oirt_vi_design.md` algorithmic spec is what a Phase 2 engineering effort would consume; the B6 R code is what they would test against.

## 3. Phase 2 carryover (concrete next steps)

1. **Cross-year vertical scaling** — use the 2025-26 review course as natural anchor items linking the 2024-25 and 2025-26 calibrations.
2. **VI/OIRT runtime** — implement the design in `docs/oirt_vi_design.md`, benchmark on a held-out OLM subset, compare against B6 Kalman as a sanity check.
3. **Teacher / class metadata join** — extend the Phase A/B ETL, then enable MT4(c).
4. **Dataset 2 (school)** — partnership + administration + analysis.
5. **RI-CLPM with a second construct** — once a second longitudinal measure is available (engagement, time-on-task, or a second-subject $\theta$), RI-CLPM becomes identifiable and informative.
6. **2PL EAP sensitivity** — confirm that switching from 1PL to 2PL (handling the 2-6% degenerate items first) does not change the catch-up→plateau headline finding.
7. **CT-DSEM full Bayesian (MCMC)** — current model uses MAP/optim; a full HMC sensitivity check for publication-grade inference.

## 4. What did NOT change

The numerical results from B0–B5 are unchanged by this scope refinement. The reliability ρ, the catch-up→plateau shift, the LGCM/LCSM/lmer/CT-DSEM parameters, and the static-vs-dynamic baseline LRT all stand exactly as previously reported. B6 and B7 are additive layers built on those outputs.

**Section numbering in the final report.** B6 and B7 are inserted as proper sequential sections after the CT-DSEM chapter — §8 (Kalman) and §9 (Applications) — so the table of contents reads B0→…→B4→B5(consolidation/diagnostics)→B6→B7 in order. Downstream sections shift accordingly: Cross-grade Pattern §10, Discussion §11, Limitations §12, Conclusion §13, Reproducibility §14. Subsection content is preserved verbatim apart from cross-reference numbers.
