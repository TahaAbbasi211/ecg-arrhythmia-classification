/// Input units and polarity, mirrored by app/signal_io.py.
library;

/// A filtered ECG in mV spans roughly 0.5 .. 5 mV between its 1st and 99th
/// percentile. Far outside that range the input unit is almost certainly wrong.
const double lowAmplitude = 0.05;
const double highAmplitude = 20.0;

/// Unit of the numbers in the file or the demo record.
enum SignalUnit { millivolt, volt, microvolt }

/// Factor that turns [unit] into millivolts.
double unitFactor(SignalUnit unit) {
  switch (unit) {
    case SignalUnit.millivolt:
      return 1.0;
    case SignalUnit.volt:
      return 1000.0;
    case SignalUnit.microvolt:
      return 0.001;
  }
}

/// Scale [values] to millivolts and optionally flip the polarity.
///
/// A non-finite sample stays NaN on purpose: the pipeline interpolates short
/// gaps and refuses a file that is mostly broken.
List<double> applySignalUnit(
  List<double> values,
  SignalUnit unit, {
  bool invert = false,
}) {
  final factor = unitFactor(unit);
  final sign = invert ? -1.0 : 1.0;
  return <double>[
    for (final value in values) value.isFinite ? value * factor * sign : double.nan,
  ];
}

/// The unit a filtered amplitude suggests, or null when it looks like mV.
SignalUnit? suggestUnitFor(double amplitude) {
  if (amplitude < lowAmplitude) return SignalUnit.volt;
  if (amplitude > highAmplitude) return SignalUnit.microvolt;
  return null;
}