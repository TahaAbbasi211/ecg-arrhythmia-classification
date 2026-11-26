"""Smoke tests for the Streamlit app: it must run, not just import."""

import ast
import os
import re

import pytest
import streamlit as st
from streamlit.testing.v1 import AppTest

APP = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "app", "streamlit_app.py")


def _app():
    app = AppTest.from_file(APP, default_timeout=180)
    app.run()
    assert not app.exception, [str(e) for e in app.exception]
    return app


def test_sample_record_analyzes_without_exceptions():
    app = _app()
    metrics = {m.label: m.value for m in app.metric}
    # The default sample is record_100.csv; these are its v3.1 numbers.
    assert int(metrics["Beats analyzed"]) == 73
    assert metrics["Heart rate (bpm)"] == "75"
    assert int(metrics["Supraventricular (S)"]) == 5
    assert int(metrics["Ventricular (V)"]) == 0
    # The plot controls rendered, including the start-time slider the 60 s sample needs.
    assert [s.label for s in app.slider][:2] == ["Window length (seconds)",
                                                "Start time (seconds)"]
    # Abnormal-beat table reports normalized relative score instead of raw probability.
    assert len(app.dataframe) == 1
    df = app.dataframe[0].value
    assert "score" in df.columns
    assert "probability" not in df.columns
    assert any("uncalibrated" in str(c.value).lower() for c in app.caption)
    # About expander reflects v3.1 metrics and record 232 limitation.
    about_md = "\n".join(str(m.value) for m in app.markdown)
    assert "0.701" in about_md
    assert "SVDB" in about_md
    assert "232" in about_md
    assert not app.error


def test_upload_tab_offers_the_unit_and_polarity_controls():
    app = AppTest.from_file(APP, default_timeout=180)
    app.run()
    app.sidebar.radio[0].set_value("Upload CSV").run()
    assert not app.exception, [str(e) for e in app.exception]
    assert any("Upload a CSV" in str(info.value) for info in app.info)

    labels = [box.label for box in app.sidebar.selectbox]
    labels += [box.label for box in app.sidebar.checkbox]
    assert "Input unit" in labels
    assert "Invert polarity" in labels


def _load_stretch_width_kwargs():
    with open(APP, encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename=APP)
    fn_node = next(
        node for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "_stretch_width_kwargs"
    )
    namespace = {"re": re, "st": st}
    exec(compile(ast.Module(body=[fn_node], type_ignores=[]), APP, "exec"), namespace)
    return namespace["_stretch_width_kwargs"]


@pytest.mark.parametrize("version,expected", [
    ("1.35.0", {"use_container_width": True}),
    ("1.45.1", {"use_container_width": True}),
    ("1.48.9", {"use_container_width": True}),
    ("1.48.1rc1", {"use_container_width": True}),
    ("1.45.1.dev0", {"use_container_width": True}),
    ("1.49.0", {"width": "stretch"}),
    ("1.49.0rc1", {"width": "stretch"}),
    ("1.49.0.dev20250101", {"width": "stretch"}),
    ("1.67.0", {"width": "stretch"}),
    ("2.0.0", {"width": "stretch"}),
    ("unknown", {"use_container_width": True}),
])
def test_stretch_width_kwargs_handles_streamlit_versions(monkeypatch, version, expected):
    fn = _load_stretch_width_kwargs()
    assert fn(version) == expected
    monkeypatch.setattr(st, "__version__", version)
    assert fn() == expected
