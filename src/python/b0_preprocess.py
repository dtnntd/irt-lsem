"""B0: Preprocessing — Convert Phase D submissions → response_long per (HS, day)."""
import csv
import json
import logging
from collections import defaultdict
from datetime import datetime, timezone, timedelta
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from utils.config import (
    PHASE_D, PHASE_C, OUTPUT_DIR, LOG_DIR, B0_CONFIG, SEED,
)

# Timezone offset for Asia/Ho_Chi_Minh = UTC+7
TZ_OFFSET = timedelta(hours=7)


def timestamp_to_date(ts: int) -> str:
    """Convert unix timestamp to date string (YYYY-MM-DD) in VN timezone."""
    dt = datetime.fromtimestamp(ts, tz=timezone.utc) + TZ_OFFSET
    return dt.strftime("%Y-%m-%d")


def load_submission_catalog(grade: int) -> dict:
    """Load catalog: id_cate → {type, type_group}."""
    catalog = {}
    path = PHASE_D / f"grade_{grade}" / "submission_catalog.csv"
    with open(path, "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            catalog[row["id_cate"]] = {
                "type": int(row["type"]),
                "type_group": row["type_group"],
            }
    return catalog


def load_student_timeline(grade: int) -> dict:
    """Load timeline: (iduser, id_cate) → time_init."""
    timeline = {}
    path = PHASE_D / f"grade_{grade}" / "student_timeline.csv"
    with open(path, "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            key = (row["iduser"], row["id_cate"])
            timeline[key] = int(row["time_init"])
    return timeline


def process_grade(grade: int, type_group: str) -> dict:
    """Process one grade + type_group → response_long CSV."""
    logging.info(f"Processing grade {grade}, type_group={type_group}")

    catalog = load_submission_catalog(grade)
    timeline = load_student_timeline(grade)

    # Filter cates by type_group
    valid_cates = {cid for cid, info in catalog.items() if info["type_group"] == type_group}
    logging.info(f"  Valid cates ({type_group}): {len(valid_cates)}")

    # Read all submissions for valid cates, attach time_init
    # Structure: (iduser, date, question_id) → is_correct (keep first if dup)
    responses = {}  # (iduser, date, question_id) → is_correct
    n_rows_read = 0
    n_cates_read = 0

    sub_dir = PHASE_D / f"grade_{grade}" / "submissions"
    for cate_file in sub_dir.glob("cate_*.csv"):
        id_cate = cate_file.stem.split("_")[1]
        if id_cate not in valid_cates:
            continue

        n_cates_read += 1
        with open(cate_file, "r", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                iduser = row["iduser"]
                question_id = row["question_id"]
                is_correct = int(row["is_correct"])

                # Get time_init from timeline
                key = (iduser, id_cate)
                time_init = timeline.get(key)
                if time_init is None:
                    continue

                date = timestamp_to_date(time_init)
                resp_key = (iduser, date, question_id)

                # Dedup: keep first
                if resp_key not in responses:
                    responses[resp_key] = (is_correct, time_init)
                n_rows_read += 1

    logging.info(f"  Read {n_rows_read:,} rows from {n_cates_read} cates")
    logging.info(f"  After dedup: {len(responses):,} unique (HS, date, question)")

    # Group by (iduser, date) → count items per day
    day_items = defaultdict(int)  # (iduser, date) → n_items
    for (iduser, date, _) in responses:
        day_items[(iduser, date)] += 1

    # Filter: min_items_per_day
    min_items = B0_CONFIG["min_items_per_day"]
    valid_days = {k for k, v in day_items.items() if v >= min_items}
    logging.info(f"  Days with ≥{min_items} items: {len(valid_days):,}")

    # Filter responses to valid days only
    filtered = {k: v for k, v in responses.items() if (k[0], k[1]) in valid_days}

    # Count days per student
    student_days = defaultdict(set)
    for (iduser, date, _) in filtered:
        student_days[iduser].add(date)

    # Filter: min_days_per_student
    min_days = B0_CONFIG["min_days_per_student"]
    valid_students = {u for u, days in student_days.items() if len(days) >= min_days}
    logging.info(f"  Students with ≥{min_days} days: {len(valid_students):,}")

    # Final filter
    final = {k: v for k, v in filtered.items() if k[0] in valid_students}
    logging.info(f"  Final responses: {len(final):,}")

    # Assign day_idx per student (sorted by date)
    student_dates_sorted = {}
    for iduser in valid_students:
        dates = sorted(student_days[iduser])
        student_dates_sorted[iduser] = {d: idx for idx, d in enumerate(dates)}

    # Write response_long CSV
    out_dir = OUTPUT_DIR / "b0_preprocessed"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"response_long_grade_{grade}_{type_group}.csv"

    fieldnames = ["iduser", "day_idx", "date", "question_id", "is_correct"]
    n_written = 0
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for (iduser, date, question_id), (is_correct, _) in sorted(final.items()):
            if iduser not in student_dates_sorted:
                continue
            day_idx = student_dates_sorted[iduser].get(date)
            if day_idx is None:
                continue
            writer.writerow({
                "iduser": iduser,
                "day_idx": day_idx,
                "date": date,
                "question_id": question_id,
                "is_correct": is_correct,
            })
            n_written += 1

    logging.info(f"  Written {n_written:,} rows → {out_path}")

    # Write day_mapping (precompute n_items)
    day_item_counts = defaultdict(int)
    for (iduser, date, _) in final:
        day_item_counts[(iduser, date)] += 1

    day_map_path = out_dir / f"day_mapping_grade_{grade}_{type_group}.csv"
    with open(day_map_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["iduser", "day_idx", "date", "n_items"])
        writer.writeheader()
        for iduser in sorted(valid_students):
            for date, day_idx in sorted(student_dates_sorted[iduser].items(), key=lambda x: x[1]):
                writer.writerow({
                    "iduser": iduser,
                    "day_idx": day_idx,
                    "date": date,
                    "n_items": day_item_counts[(iduser, date)],
                })

    # Summary stats
    T_values = [len(dates) for dates in student_days.values() if len(dates) >= min_days]
    T_values.sort()
    n = len(T_values)
    summary = {
        "grade": grade,
        "type_group": type_group,
        "n_students": len(valid_students),
        "n_responses": n_written,
        "n_items_unique": len({k[2] for k in final}),
        "n_days_total": len(valid_days & {(u, d) for u in valid_students for d in student_days[u]}),
        "median_T": T_values[n // 2] if n > 0 else 0,
        "p90_T": T_values[int(n * 0.9)] if n > 0 else 0,
        "p95_T": T_values[int(n * 0.95)] if n > 0 else 0,
        "max_T": T_values[-1] if n > 0 else 0,
    }
    logging.info(f"  Summary: {summary}")
    return summary


def main():
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_file = LOG_DIR / f"b0_{datetime.now():%Y%m%d_%H%M%S}.log"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[logging.FileHandler(log_file), logging.StreamHandler()],
    )

    logging.info("=" * 60)
    logging.info("B0: PREPROCESSING")
    logging.info(f"Config: {B0_CONFIG}")
    logging.info("=" * 60)

    all_summaries = []
    for grade in B0_CONFIG["grades"]:
        for type_group in ["exam", "practice"]:
            summary = process_grade(grade, type_group)
            all_summaries.append(summary)
            print(f"  ✓ Grade {grade} {type_group}: "
                  f"{summary['n_students']:,} HS, {summary['n_responses']:,} resp, "
                  f"median T={summary['median_T']}")

    # Save summary
    out_dir = OUTPUT_DIR / "b0_preprocessed"
    with open(out_dir / "b0_summary.json", "w") as f:
        json.dump(all_summaries, f, indent=2)

    logging.info("B0 complete.")


if __name__ == "__main__":
    main()
