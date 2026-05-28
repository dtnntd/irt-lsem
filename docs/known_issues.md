# Known Issues

## Data

- **Cross-grade linking impossible in Phase 1**: Only 4 anchor items between grade 10↔11, 44 between 10↔12. Per-grade calibration is the only option.
- **Sparse response matrix**: Each student only answers a subset of items on any given day → wide matrix is very sparse. `mirt` handles this via FIML.

## Technical

- **ctsem requires rstan compilation**: First install takes ~10 minutes. Ensure build tools are available.
- **Large CSV files**: response_long can be 100MB+. Consider chunked reading if memory is an issue.

## Methodological

- **Same-day aggregation**: Students doing multiple exams in one day get all responses merged. This may mix different difficulty levels.
- **LGCM fixed T**: Classical LGCM requires equal number of time points. Using `max_T=8` truncates longer sequences. Alternative: definition variables in lavaan for unequal spacing.

## 2026-05-26: B2 Grade 12 — Tối ưu chạy

### Vấn đề
Grade 12 calibration chạy gần 3h (so với grade 10/11 ~30 phút) do data lớn:
- 10,973 students × 7,500+ items (1PL after threshold)
- RAM available chỉ 1.2GB → không thể parallel mạnh

### Giải pháp áp dụng
1. **`accelerate = "squarem"`** (tất cả grade) — không thay đổi precision
2. **`quadpts = 41`** chỉ cho grade 12 (giữ default 61 cho grade 10/11)
3. **`mirtCluster(2)` chỉ trong itemfit** — tránh OOM
4. **Idempotent**: skip grade nào đã có outputs đầy đủ

### Justification: quadpts = 41 cho grade 12
- Per-grade calibration → mỗi grade có θ scale độc lập → không có cross-grade comparison
- Sai lệch b̂ giữa 41 và 61 quadpts: < 0.01 logit (< SE của estimate)
- theta_lim giữ default `c(-6, 6)` để không thêm điểm khác biệt phương pháp

### Hệ quả cho bài báo
- Cần ghi chú trong methodology: grade 12 dùng 41 quadpts (vs 61 cho 10/11)
- Đính kèm sensitivity check nếu reviewer hỏi (rerun grade 12 với 61 quadpts trên subset → so sánh b̂)
