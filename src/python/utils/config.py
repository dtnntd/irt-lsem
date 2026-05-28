"""Shared configuration and paths for the IRT-LSEM research project."""
from pathlib import Path

# === PATHS ===
# config.py is at: research/irt_lsem/src/python/utils/config.py
# PROJECT_ROOT = research/irt_lsem/
_THIS_FILE = Path(__file__).resolve()
PROJECT_ROOT = _THIS_FILE.parent.parent.parent.parent  # src/python/utils → src/python → src → irt_lsem
DATA_ROOT = PROJECT_ROOT.parent.parent / "data"  # irt_lsem → research → olm_irt → olm_irt/data
OUTPUT_DIR = PROJECT_ROOT / "outputs"
LOG_DIR = PROJECT_ROOT / "logs"

# Phase data (read-only)
PHASE_A = DATA_ROOT / "phase_a"
PHASE_B = DATA_ROOT / "phase_b"
PHASE_C = DATA_ROOT / "phase_c"
PHASE_D = DATA_ROOT / "phase_d"

# === B0 CONFIG ===
B0_CONFIG = {
    "timezone": "Asia/Ho_Chi_Minh",
    "min_items_per_day": 10,
    "min_days_per_student": 3,
    "dedup_strategy": "first",  # keep first response if duplicate (iduser, day, question)
    "grades": [10, 11, 12],
    "exam_types": {13, 14, 21},  # type_group = "exam"
    "valid_types": {3, 4, 13, 14, 16, 18, 20, 21},
}

# === IRT CONFIG ===
IRT_CONFIG = {
    "min_resp_1pl": 50,
    "min_resp_2pl": 200,
    "eap_prior_mean": 0.0,
    "eap_prior_sd": 1.0,
}

# === LSEM CONFIG ===
LSEM_CONFIG = {
    "lgcm_max_T": 8,
    "dsem_min_T": 15,  # grade 12 only
    "estimator": "MLR",
}

# === RANDOM SEED ===
SEED = 42
