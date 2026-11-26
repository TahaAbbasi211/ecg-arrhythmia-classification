"""Signal-file parsing shared by the Streamlit app and the Python tests.

Kept free of any Streamlit import so it can be unit tested, and deliberately
mirrored by mobile/lib/data/signal_parser.dart:

* blank lines, BOM characters and # or // comments are ignored;
* a text first line is treated as the header;
* the time column of a (time, ecg) file is detected and never used as the ECG;
* non-numeric fields become NaN, and inf becomes NaN too, so nothing broken can
  reach the zero-phase filters.
"""

import io
import re

import numpy as np
import pandas as pd

COMMENT_PREFIXES = ("#", "//")
TIME_HEADER_HINTS = ("time", "sec", "timestamp", "index", "idx", "sample")

# A filtered ECG in mV has a p99 - p1 spread of roughly 0.5 .. 5 mV.
LOW_AMPLITUDE = 0.05
HIGH_AMPLITUDE = 20.0

UNIT_MV = "mV (default)"
UNIT_VOLTS = "V (x1000)"
UNIT_MICROVOLTS = "uV (x0.001)"
UNIT_FACTORS = {UNIT_MV: 1.0, UNIT_VOLTS: 1000.0, UNIT_MICROVOLTS: 0.001}


def decode_uploaded(data):
    """Decode raw bytes, tolerating a BOM and non-UTF-8 legacy encodings."""
    if not data:
        raise ValueError("that file is empty")
    for encoding in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise ValueError("that file is not UTF-8 or Latin-1 text")


def _fields(line):
    return [part.strip() for part in re.split(r"[,;\t]", line) if part.strip()]


def _as_number(token):
    try:
        return float(token)
    except (TypeError, ValueError):
        return None


def data_lines(text):
    """Drop blank lines, BOM characters and # or // comments."""
    lines = []
    for raw in text.splitlines():
        stripped = raw.strip().lstrip("\ufeff")
        if not stripped or stripped.startswith(COMMENT_PREFIXES):
            continue
        lines.append(stripped)
    return lines


def _delimiter(lines):
    """Guess the field separator from the first lines (None means one column)."""
    counts = {",": 0, ";": 0, "\t": 0}
    for line in lines[:20]:
        for separator in counts:
            counts[separator] += line.count(separator)
    best = max(counts, key=counts.get)
    return best if counts[best] > 0 else None


def read_signal_frame(text):
    """Parse a CSV/text signal into a numeric DataFrame, keeping header names."""
    lines = data_lines(text)
    if not lines:
        raise ValueError("that file has no data rows (only blank lines or comments)")

    header_names = _fields(lines[0])
    has_header = any(_as_number(token) is None for token in header_names)

    try:
        frame = pd.read_csv(
            io.StringIO("\n".join(lines)),
            sep=_delimiter(lines) or ",",
            engine="python",
            header=None,
            on_bad_lines="skip",
        )
    except Exception as exc:  # pandas raises several unrelated error types here
        raise ValueError("could not parse that file as CSV: %s" % exc) from exc

    if frame.empty:
        raise ValueError("that file has no readable rows")

    if has_header:
        frame = frame.iloc[1:].reset_index(drop=True)

    # errors="coerce" turns junk into NaN, but it keeps "inf" / "-inf" as they are.
    frame = frame.apply(pd.to_numeric, errors="coerce")
    if frame.empty or not frame.notna().to_numpy().any():
        raise ValueError("that file contains no numbers")

    seen = {}
    names = []
    for i in range(frame.shape[1]):
        name = header_names[i] if has_header and i < len(header_names) else ""
        name = name or "column %d" % (i + 1)
        if name in seen:
            seen[name] += 1
            name = "%s (%d)" % (name, seen[name])
        else:
            seen[name] = 1
        names.append(name)
    frame.columns = names

    # A text column ("units", "lead name") simply has no numeric value.
    frame = frame[[column for column in frame.columns if frame[column].notna().any()]]
    if frame.empty:
        raise ValueError("that file contains no numbers")
    return frame


def _has_time_header(name):
    """True when the column header names a time or sample-index axis."""
    lowered = str(name).strip().lower()
    # A single "t" must be an exact match: "voltage" or "rate" contain it.
    if lowered == "t":
        return True
    return any(hint in lowered for hint in TIME_HEADER_HINTS)


def _looks_like_time_values(values):
    """True for a strictly increasing, evenly spaced numeric sequence."""
    values = np.asarray(values, dtype=float)
    if values.size < 2 or not np.all(np.isfinite(values)):
        return False
    diffs = np.diff(values)
    if not np.all(diffs > 0):
        return False
    step = float(np.median(diffs))
    if step <= 0:
        return False
    # Writers round the time axis, so allow a few percent of jitter.
    return bool(np.max(np.abs(diffs - step)) <= 0.05 * step)


def looks_like_time(name, values):
    """True for a header that says 'time', or a strictly increasing, even column."""
    return _has_time_header(name) or _looks_like_time_values(values)


def heart_rate_bpm(peaks, fs):
    """Median-interval heart rate, or None when two beats cannot be compared."""
    peaks = np.asarray(peaks, dtype=float)
    if peaks.size < 2:
        return None
    rr = np.diff(np.sort(peaks))
    rr = rr[np.isfinite(rr) & (rr > 0)]
    if rr.size == 0:
        return None
    bpm = 60.0 * float(fs) / float(np.median(rr))
    return bpm if np.isfinite(bpm) else None


def describe_columns(frame):
    """Return (signal candidates, detected time column label or None)."""
    usable = [column for column in frame.columns if frame[column].notna().sum() >= 2]
    if not usable:
        raise ValueError("that file has no numeric column with at least two values")

    time_columns = [column for column in usable if _has_time_header(column)]
    remaining = [column for column in usable if column not in set(time_columns)]
    if not remaining:
        raise ValueError("that file only holds a time axis, no ECG values")

    monotonic = [
        column for column in remaining
        if _looks_like_time_values(frame[column].to_numpy(dtype=float))
    ]
    non_monotonic = [column for column in remaining if column not in set(monotonic)]
    if non_monotonic:
        time_set = set(time_columns) | set(monotonic)
        time_columns = [column for column in usable if column in time_set]
        candidates = non_monotonic
    elif time_columns:
        candidates = remaining
    else:
        raise ValueError("that file only holds a time axis, no ECG values")

    time_column = ", ".join(time_columns) if time_columns else None
    return candidates, time_column


def apply_unit(values, unit, invert=False):
    """Scale a signal to millivolts and optionally flip its polarity."""
    factor = UNIT_FACTORS.get(unit, 1.0)
    scaled = np.asarray(values, dtype=float) * factor
    if invert:
        scaled = -scaled
    # inf cannot pass through filtfilt; treat it as a missing sample so the
    # pipeline's sanitize step interpolates it (and rejects a fully broken file).
    return np.where(np.isfinite(scaled), scaled, np.nan)