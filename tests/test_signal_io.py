"""Streamlit-side parsing and unit handling (app/signal_io.py)."""

import numpy as np
import pytest

from app.signal_io import (
    HIGH_AMPLITUDE,
    LOW_AMPLITUDE,
    UNIT_MICROVOLTS,
    UNIT_MV,
    UNIT_VOLTS,
    apply_unit,
    data_lines,
    decode_uploaded,
    describe_columns,
    heart_rate_bpm,
    looks_like_time,
    read_signal_frame,
)


def test_a_header_named_t_is_a_time_axis_but_voltage_is_not():
    # A single 't' would also match 'voltage' or 'rate' with substring rules.
    assert looks_like_time('t', np.array([0.0, 0.02, 0.05]))
    assert not looks_like_time('voltage', np.array([0.0, 0.02, 0.05]))
    assert not looks_like_time('rate', np.array([0.0, 0.02, 0.05]))
    frame = read_signal_frame('voltage,value\n0.9,1\n0.1,2\n0.05,3\n')
    candidates, time_name = describe_columns(frame)
    assert time_name == 'value'
    assert candidates == ['voltage']


def test_decode_uploaded_handles_bom_and_latin1():
    assert decode_uploaded("\ufeff1\n2\n".encode("utf-8")) == "1\n2\n"
    assert decode_uploaded("mV\n1,2\n".encode("latin-1")) == "mV\n1,2\n"
    with pytest.raises(ValueError):
        decode_uploaded(b"")


def test_data_lines_skips_comments_and_blank_lines():
    text = "\ufeff# header comment\n\n0.5\n// note\n0.7\n  \n"
    assert data_lines(text) == ["0.5", "0.7"]


def test_single_column_file_keeps_its_header_name():
    frame = read_signal_frame("MLII_mV\n0.86\n0.765\n0.645\n")
    assert list(frame.columns) == ["MLII_mV"]
    assert frame["MLII_mV"].tolist() == [0.86, 0.765, 0.645]


def test_two_column_file_drops_the_time_axis():
    frame = read_signal_frame("time,mV\n0.0,1.5\n0.1,2.5\n0.2,3.5\n")
    candidates, time_column = describe_columns(frame)
    assert time_column == "time"
    assert candidates == ["mV"]
    assert frame["mV"].tolist() == [1.5, 2.5, 3.5]


def test_two_rows_are_enough_to_recognize_a_time_column():
    frame = read_signal_frame("t,value\n0,1.5\n1,2.5\n")
    candidates, time_column = describe_columns(frame)
    assert time_column == "t"
    assert candidates == ["value"]
    assert frame["value"].tolist() == [1.5, 2.5]


def test_monotonic_column_without_a_header_is_still_time():
    values = np.array([0.0, 0.008, 0.016, 0.024])
    assert looks_like_time("column 1", values)
    assert not looks_like_time("column 1", np.array([0.86, 0.765, 0.645]))


def test_comment_lines_never_become_samples():
    frame = read_signal_frame("# recorded with a 0.5-40 Hz filter\n1.0\n// 2.0\n3.0\n")
    assert frame[frame.columns[0]].tolist() == [1.0, 3.0]


def test_junk_fields_become_nan_instead_of_shifting_time():
    frame = read_signal_frame("t,mV\n0,1.0\n1,x\n2,3.0\n")
    values = frame["mV"].to_numpy(dtype=float)
    assert values[0] == 1.0
    assert np.isnan(values[1])
    assert values[2] == 3.0


def test_infinite_text_reaches_apply_unit_and_turns_into_nan():
    # pandas keeps "inf" as a number on purpose; the unit step is what turns
    # every non-finite sample into NaN, so the filters can interpolate it.
    frame = read_signal_frame("1.0\ninf\n2.0\n")
    values = apply_unit(frame[frame.columns[0]].to_numpy(dtype=float), UNIT_MV)
    assert np.isnan(values[1])
    assert values[0] == 1.0 and values[2] == 2.0


@pytest.mark.parametrize("text", ["", "\n\n", "# only comments\n"])
def test_empty_files_raise_a_clear_error(text):
    with pytest.raises(ValueError):
        read_signal_frame(text)


def test_files_without_numbers_raise_a_clear_error():
    with pytest.raises(ValueError, match="no numbers"):
        read_signal_frame("lead,unit\nMLII,mV\n")


def test_only_a_time_axis_raises_a_clear_error():
    with pytest.raises(ValueError, match="only holds a time axis"):
        describe_columns(read_signal_frame("time\n0.0\n0.1\n0.2\n"))


def test_unit_factors_and_polarity():
    values = np.array([0.001, -0.002])
    assert np.allclose(apply_unit(values, UNIT_MV), values)
    assert np.allclose(apply_unit(values, UNIT_VOLTS), values * 1000.0)
    assert np.allclose(apply_unit(values, UNIT_MICROVOLTS), values * 0.001)
    assert np.allclose(apply_unit(values, UNIT_MV, invert=True), -values)


def test_inf_becomes_nan_so_filters_can_interpolate_it():
    scaled = apply_unit(np.array([1.0, np.inf, -np.inf, np.nan]), UNIT_MV)
    assert scaled[0] == 1.0
    assert np.isnan(scaled[1:]).all()


def test_a_volts_file_is_flagged_as_suspicious_after_filtering():
    # 1 mV of ECG written in volts: read as mV it spans 0.002 units, which is
    # below the warning bound; declared as volts it becomes a normal 2 mV ECG.
    raw_volts = np.array([0.001, -0.001, 0.001, -0.001])
    as_mv = apply_unit(raw_volts, UNIT_MV)
    assert float(np.ptp(as_mv)) < LOW_AMPLITUDE
    as_volts = apply_unit(raw_volts, UNIT_VOLTS)
    assert float(np.ptp(as_volts)) > 1.0

    # Raw ADC counts are far above millivolts.
    adc = np.array([0.0, 900.0, -700.0, 0.0])
    assert float(np.ptp(adc)) > HIGH_AMPLITUDE


def test_heart_rate_is_finite_for_three_peaks():
    bpm = heart_rate_bpm(np.array([100, 110, 120]), 360)
    assert bpm is not None and np.isfinite(bpm)
    assert bpm == pytest.approx(2160.0)
    assert heart_rate_bpm(np.array([100]), 360) is None
    assert heart_rate_bpm(np.array([]), 360) is None
    # Two peaks on top of each other would divide by zero.
    assert heart_rate_bpm(np.array([100, 100]), 360) is None


def test_heart_rate_format_never_prints_nan():
    bpm = heart_rate_bpm(np.array([10, 300, 590]), 360)
    text = "—" if bpm is None else "%.0f" % bpm
    assert "nan" not in text.lower()


def test_three_column_sample_time_ecg_drops_both_non_signal_columns():
    csv = "sample,time_s,MLII_mV\n0,0.000,0.12\n1,0.003,0.45\n2,0.006,-0.20\n"
    frame = read_signal_frame(csv)
    candidates, time_column = describe_columns(frame)
    assert candidates == ["MLII_mV"]
    assert frame[candidates[0]].tolist() == [0.12, 0.45, -0.20]
    assert time_column == "sample, time_s"
