"""Write export/resample_parity.json: the Python resampler turned into a fixture.

The Android app mirrors src/portable.py in mobile/lib/ecg/resample.dart. Both
the pytest suite and the Dart suite compare against this file, so a divergence
in either language fails a test instead of silently changing the beats.

Usage:
    python scripts/export_resample_parity.py
"""

import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from src import portable  # noqa: E402

OUT = os.path.join(ROOT, "export", "resample_parity.json")
RATES = (180, 250, 500)
SECONDS = 6.0


def synthetic(fs):
    """A PQRST-ish mix plus a narrow spike, so the anti-alias step matters."""
    n = int(round(fs * SECONDS))
    t = np.arange(n) / fs
    x = (0.8 * np.sin(2 * np.pi * 1.2 * t)
         + 0.3 * np.sin(2 * np.pi * 17.0 * t)
         + 0.05 * np.sin(2 * np.pi * 60.0 * t))
    center = int(0.5 * n)
    x[center:center + 3] += 2.5
    return np.round(x, 6)


def main():
    cases = []
    for fs in RATES:
        raw = synthetic(fs)
        expected = portable.to_360hz(raw, fs)
        cases.append({
            "fs": fs,
            "raw": [float(v) for v in raw],
            "expected": [round(float(v), 9) for v in expected],
        })
        print("%d Hz -> %d samples (expected %d)" % (fs, len(raw), len(expected)))

    payload = {"target": portable.TARGET_FS, "cases": cases}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"))
    print("wrote %s (%d bytes)" % (OUT, os.path.getsize(OUT)))


if __name__ == "__main__":
    main()