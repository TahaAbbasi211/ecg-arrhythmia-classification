"""Shared fixtures for the pytest suite.

The suite runs from any directory: the repository root is added to sys.path.
"""

import json
import os
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)


@pytest.fixture(scope="session")
def root():
    return ROOT


@pytest.fixture(scope="session")
def bundle():
    from src.pipeline import load_model

    return load_model(os.path.join(ROOT, "models", "ecg_rf_small.joblib"))


@pytest.fixture(scope="session")
def vectors(root):
    with open(os.path.join(root, "export", "test_vectors.json"), encoding="utf-8") as handle:
        return json.load(handle)


@pytest.fixture(scope="session")
def parity(root):
    with open(os.path.join(root, "export", "resample_parity.json"), encoding="utf-8") as handle:
        return json.load(handle)


@pytest.fixture(scope="session")
def record_200(root):
    """The bundled 60 s record 200, from the same CSV the Android app ships."""
    from app.signal_io import read_signal_frame

    path = os.path.join(root, "mobile", "assets", "samples", "record_200.csv")
    with open(path, encoding="utf-8-sig") as handle:
        frame = read_signal_frame(handle.read())
    return frame[frame.columns[-1]].to_numpy(dtype=float)
