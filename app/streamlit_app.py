
import os
import sys

import numpy as np
import pandas as pd
import streamlit as st
import matplotlib.pyplot as plt


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(ROOT)

from src.pipeline import analyze_portable, load_model, CLASSES

SAMPLES_DIR = os.path.join(ROOT, "app", "samples")
MODEL_PATH = os.path.join(ROOT, "models", "ecg_rf_small.joblib")

COLORS = {"N": "#2e9e5b", "S": "#f0a020", "V": "#d63a3a"}
NAMES = {
    "N": "Normal",
    "S": "Supraventricular premature",
    "V": "Ventricular premature",
}

st.set_page_config(page_title="ECG Arrhythmia Classifier", page_icon="🫀", layout="wide")


@st.cache_resource
def get_model():
    return load_model(MODEL_PATH)


@st.cache_data
def run_analysis(sig, fs):
        return analyze_portable(sig, fs, get_model())


st.title("🫀 ECG Arrhythmia Classifier")
st.caption("Classifies each heartbeat as Normal (N), Supraventricular premature (S) "
           "or Ventricular premature (V). Educational project, not a medical device.")

# ---------- input ----------
source = st.sidebar.radio("Signal source", ["Sample record", "Upload CSV"])

if source == "Sample record":
    samples = sorted(f for f in os.listdir(SAMPLES_DIR) if f.endswith(".csv"))
    name = st.sidebar.selectbox("Sample", samples)
    sig = pd.read_csv(os.path.join(SAMPLES_DIR, name)).iloc[:, 0].to_numpy()
    fs = 360
else:
    fs = int(st.sidebar.number_input("Sampling rate (Hz)", min_value=100,
                                     max_value=2000, value=360, step=1))
    up = st.sidebar.file_uploader("CSV with one column of ECG samples (mV)",
                                  type=["csv", "txt"])
    if up is None:
        st.info("Upload a CSV file to start.")
        st.stop()
    col = pd.read_csv(up, header=None).iloc[:, 0]
    sig = pd.to_numeric(col, errors="coerce").dropna().to_numpy()

if len(sig) < 10 * fs:
    st.error("The signal is too short. Please provide at least 10 seconds of ECG.")
    st.stop()

# ---------- analysis ----------
with st.spinner("Analyzing..."):
    res = run_analysis(sig, fs)

peaks, pred, proba = res["peaks"], res["pred"], res["proba"]
sig_f, fs_ = res["signal"], res["fs"]

if len(peaks) == 0:
    st.warning("No heartbeats could be detected in this signal.")
    st.stop()

labels = np.array(CLASSES)[pred]
duration = len(sig_f) / fs_
hr = 60 * fs_ / np.median(np.diff(peaks)) if len(peaks) > 1 else float("nan")

c1, c2, c3, c4 = st.columns(4)
c1.metric("Beats analyzed", len(peaks))
c2.metric("Heart rate (bpm)", f"{hr:.0f}")
c3.metric("Supraventricular (S)", int((labels == "S").sum()))
c4.metric("Ventricular (V)", int((labels == "V").sum()))

# ---------- plot ----------
win = st.slider("Window length (seconds)", 3, 15, 8)
max_start = duration - win
if max_start > 0:
    start = st.slider("Start time (seconds)", 0.0, float(max_start), 0.0, step=0.5)
else:
    start = 0.0

i0, i1 = int(start * fs_), min(int((start + win) * fs_), len(sig_f))
t = np.arange(i0, i1) / fs_

fig, ax = plt.subplots(figsize=(12, 3.5))
ax.plot(t, sig_f[i0:i1], lw=1, color="#333")
in_win = (peaks >= i0) & (peaks < i1)
for c in ["N", "S", "V"]:
    sel = in_win & (labels == c)
    ax.scatter(peaks[sel] / fs_, sig_f[peaks[sel]], s=40, color=COLORS[c],
               label=f"{c} - {NAMES[c]}", zorder=3)
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
    st.dataframe(beats[beats["class"] != "N"], height=250, use_container_width=True)

with st.expander("About this model"):
    st.markdown(
        "- Random Forest (50 trees) trained on the MIT-BIH Arrhythmia Database (22 training patients).\n"
        "- Evaluated on 22 different patients (inter-patient split).\n"
        "- Test F1: **N 0.965**, **V 0.926**, **S 0.180**. S beats look very similar to normal "
        "beats, so this class is weak.\n"
        "- Fusion (F) beats are not predicted: there was too little training data and "
        "boosting them caused many false alarms.\n"
        "- Not validated on other devices or populations. Not for diagnosis."
    )