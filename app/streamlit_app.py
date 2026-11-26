"""Streamlit demo for the ECG beat classifier.

The parsing rules here mirror mobile/lib/data/signal_parser.dart (comments, a
(time, ecg) two-column layout) and the Android input options (unit, polarity).
"""

import os
import re
import sys

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import streamlit as st

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.signal_io import (  # noqa: E402
    HIGH_AMPLITUDE,
    LOW_AMPLITUDE,
    UNIT_FACTORS,
    UNIT_MICROVOLTS,
    UNIT_MV,
    UNIT_VOLTS,
    apply_unit,
    decode_uploaded,
    describe_columns,
    heart_rate_bpm,
    read_signal_frame,
)
from src.pipeline import CLASSES, analyze_portable, load_model  # noqa: E402
from src.portable import SignalError  # noqa: E402

SAMPLES_DIR = os.path.join(ROOT, "app", "samples")
MODEL_PATH = os.path.join(ROOT, "models", "ecg_rf_small.joblib")

COLORS = {"N": "#2E9E5B", "S": "#F0A020", "V": "#D63A3A"}
NAMES = {"N": "Normal", "S": "Supraventricular", "V": "Ventricular"}

st.set_page_config(page_title="ECG Arrhythmia Classifier", page_icon="🫀", layout="wide")


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------
@st.cache_resource
def get_model():
    return load_model(MODEL_PATH)


@st.cache_data(show_spinner=False)
def run_analysis(sig, fs):
    return analyze_portable(sig, fs, get_model())


def _set_unit(unit):
    st.session_state["sig_unit"] = unit


def _stretch_width_kwargs(version=None):
    """Return full-width kwargs compatible with Streamlit <1.49 and >=1.49."""
    raw = st.__version__ if version is None else version
    match = re.match(r"^\s*(\d+)(?:\.(\d+))?", str(raw))
    parsed = (int(match.group(1)), int(match.group(2) or 0)) if match else (0, 0)
    if parsed >= (1, 49):
        return {"width": "stretch"}
    return {"use_container_width": True}


st.title("🫀 ECG Arrhythmia Classifier")
st.caption(
    "Classifies each heartbeat as Normal (N), Supraventricular premature (S) "
    "or Ventricular premature (V). "
    "Research and non-clinical software — not a certified medical device and "
    "not intended for clinical diagnosis or treatment decisions."
)

# ---------- input ----------
source = st.sidebar.radio("Signal source", ["Sample record", "Upload CSV"])

if "sig_unit" not in st.session_state:
    st.session_state["sig_unit"] = UNIT_MV

raw_values = None
column_note = None

if source == "Sample record":
    samples = sorted(f for f in os.listdir(SAMPLES_DIR) if f.endswith(".csv"))
    name = st.sidebar.selectbox("Sample", samples)
    with open(os.path.join(SAMPLES_DIR, name), encoding="utf-8-sig") as handle:
        text = handle.read()
    fs = 360
    try:
        frame = read_signal_frame(text)
        candidates, time_column = describe_columns(frame)
    except ValueError as exc:
        st.error(str(exc))
        st.stop()
    signal_column = st.sidebar.selectbox("ECG column", candidates)
    raw_values = frame[signal_column].to_numpy(dtype=float)
else:
    fs = int(st.sidebar.number_input("Sampling rate (Hz)", min_value=10,
                                     max_value=2000, value=360, step=1))
    st.sidebar.selectbox("Input unit", list(UNIT_FACTORS), key="sig_unit")
    invert = st.sidebar.checkbox("Invert polarity", value=False)
    up = st.sidebar.file_uploader("CSV with one column of ECG samples, or (time, ecg)",
                                  type=["csv", "txt"])
    if up is None:
        st.info("Upload a CSV file to start.")
        st.stop()

    try:
        frame = read_signal_frame(decode_uploaded(up.getvalue()))
        candidates, time_column = describe_columns(frame)
    except ValueError as exc:
        st.error(str(exc))
        st.stop()

    signal_column = st.sidebar.selectbox("ECG column", candidates)
    if time_column is not None:
        column_note = "Using the ECG column %s (time column %s ignored)." % (
            signal_column, time_column)
    else:
        column_note = "Using the ECG column %s." % signal_column
    raw_values = frame[signal_column].to_numpy(dtype=float)

if column_note:
    st.caption(column_note)

if source == "Sample record":
    sig = apply_unit(raw_values, UNIT_MV, False)
    unit = UNIT_MV
else:
    unit = st.session_state["sig_unit"]
    sig = apply_unit(raw_values, unit, invert)

if not np.isfinite(sig).any():
    st.error("That file contains no finite numbers.")
    st.stop()

if len(sig) < 10 * fs:
    st.error("The signal is too short. Please provide at least 10 seconds of ECG.")
    st.stop()

# ---------- analysis ----------
try:
    with st.spinner("Analyzing..."):
        res = run_analysis(sig, fs)
except SignalError as exc:
    st.error(str(exc))
    st.stop()

peaks, pred, proba = res["peaks"], res["pred"], res["proba"]
sig_f, fs_ = res["signal"], res["fs"]

# Robust amplitude after the 0.5-40 Hz band-pass: a hint about the input unit,
# never an automatic conversion.
amplitude = float(np.percentile(sig_f, 99) - np.percentile(sig_f, 1)) if len(sig_f) else 0.0
if amplitude < LOW_AMPLITUDE and unit != UNIT_VOLTS:
    st.warning("The filtered signal spans only %.3f units. The file may be in volts, "
               "not millivolts (a normal ECG spans about 1 mV)." % amplitude)
    st.button("Treat the input as volts (x1000)", on_click=_set_unit, args=(UNIT_VOLTS,))
elif amplitude > HIGH_AMPLITUDE and unit != UNIT_MICROVOLTS:
    st.warning("The filtered signal spans %.0f units. The file may be in microvolts "
               "or raw ADC counts, not millivolts." % amplitude)
    st.button("Treat the input as microvolts (x0.001)",
              on_click=_set_unit, args=(UNIT_MICROVOLTS,))

if len(peaks) == 0:
    st.warning("No heartbeats could be detected in this signal.")
    st.stop()

labels = np.array(CLASSES)[pred]
duration = len(sig_f) / fs_
bpm = heart_rate_bpm(peaks, fs_)
heart_rate = "—" if bpm is None else "%.0f" % bpm

c1, c2, c3, c4 = st.columns(4)
c1.metric("Beats analyzed", len(peaks))
c2.metric("Heart rate (bpm)", heart_rate)
c3.metric("Supraventricular (S)", int((labels == "S").sum()))
c4.metric("Ventricular (V)", int((labels == "V").sum()))

# ---------- plot ----------
win = st.slider("Window length (seconds)", 3, 15, 8)
win = min(float(win), max(duration, 0.5))
max_start = duration - win
if max_start >= 0.5:
    start = st.slider("Start time (seconds)", 0.0, float(max_start), 0.0, step=0.5)
else:
    start = 0.0

i0 = int(start * fs_)
i1 = min(int((start + win) * fs_), len(sig_f))
t = np.arange(i0, i1) / fs_

fig, ax = plt.subplots(figsize=(12, 3.5))
ax.plot(t, sig_f[i0:i1], lw=1, color="#333")
in_win = (peaks >= i0) & (peaks < i1)
for c in ["N", "S", "V"]:
    sel = in_win & (labels == c)
    ax.scatter(peaks[sel] / fs_, sig_f[peaks[sel]], s=40, color=COLORS[c],
               label="%s - %s" % (c, NAMES[c]), zorder=3)
ax.set_xlabel("Time (s)")
ax.set_ylabel("Amplitude (mV)")
ax.legend(loc="lower center", bbox_to_anchor=(0.5, 1.02), ncol=3,
          fontsize=8, frameon=False)
st.pyplot(fig)
plt.close(fig)

# ---------- summary ----------
left, right = st.columns(2)
with left:
    st.subheader("Beat counts")
    counts = pd.Series(labels).value_counts().reindex(["N", "S", "V"], fill_value=0)
    st.bar_chart(counts)
with right:
    st.subheader("Detected S and V beats")
    beats = pd.DataFrame({
        "time (s)": np.round(peaks / fs_, 2),
        "class": labels,
        "probability": np.round(proba[np.arange(len(pred)), pred], 2),
    })
    st.dataframe(beats[beats["class"] != "N"], height=250, **_stretch_width_kwargs())

with st.expander("About this model"):
    st.markdown(
        "- Random Forest (50 trees) trained on the MIT-BIH Arrhythmia Database (22 training patients).\n"
        "- Evaluated on 22 different patients (inter-patient split).\n"
        "- Test F1: **N 0.965**, **V 0.923**, **S 0.177**. S beats look very similar to normal "
        "beats, so this class is weak.\n"
        "- Fusion (F) beats are not predicted: there was too little training data and "
        "boosting them caused many false alarms.\n"
        "- Not validated on other devices or populations. Research and non-clinical software — "
        "not a certified medical device and not intended for clinical diagnosis or treatment decisions."
    )