"""Smoke tests for the Streamlit app: it must run, not just import."""

import os

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
    # The default sample is record_100.csv; these are its v2.1 numbers.
    assert int(metrics["Beats analyzed"]) == 73
    assert metrics["Heart rate (bpm)"] == "75"
    assert int(metrics["Supraventricular (S)"]) == 5
    assert int(metrics["Ventricular (V)"]) == 0
    # The plot controls rendered, including the start-time slider the 60 s sample needs.
    assert [s.label for s in app.slider][:2] == ["Window length (seconds)",
                                                "Start time (seconds)"]
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
