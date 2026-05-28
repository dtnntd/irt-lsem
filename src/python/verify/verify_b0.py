"""Verification gate: B0 → B1/B2."""
import sys
import pandas as pd
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from utils.config import OUTPUT_DIR, B0_CONFIG


def verify_b0(grade: int) -> dict:
    path = OUTPUT_DIR / "b0_preprocessed" / f"response_long_grade_{grade}_exam.csv"
    if not path.exists():
        return {"file_exists": False}

    df = pd.read_csv(path)
    checks = {
        "file_exists": True,
        "no_duplicates": df.duplicated(["iduser", "day_idx", "question_id"]).sum() == 0,
        "is_correct_binary": set(df["is_correct"].unique()) <= {0, 1},
        "all_HS_min_days": df.groupby("iduser")["day_idx"].nunique().min()
        >= B0_CONFIG["min_days_per_student"],
        "all_days_min_items": df.groupby(["iduser", "day_idx"]).size().min()
        >= B0_CONFIG["min_items_per_day"],
        "day_idx_starts_zero": (df.groupby("iduser")["day_idx"].min() == 0).all(),
    }
    return checks


if __name__ == "__main__":
    all_pass = True
    for grade in B0_CONFIG["grades"]:
        checks = verify_b0(grade)
        passed = all(checks.values())
        status = "✅" if passed else "❌"
        print(f"  {status} Grade {grade}: {checks}")
        if not passed:
            all_pass = False

    sys.exit(0 if all_pass else 1)
