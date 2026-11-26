/// Parsing of raw ECG text files into a list of samples.
///
/// Mirrors app/signal_io.py: blank lines and # or // comments are skipped, a
/// text first line is the header, and the time column of a (time, ecg) file is
/// never mistaken for the ECG.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import '../ecg/stats.dart';

/// Result of parsing a CSV/text signal file.
class ParsedSignal {
  ParsedSignal({
    required this.values,
    required this.skippedLines,
    this.columnName,
    this.timeColumn,
  });

  final List<double> values;

  /// Lines that held no usable number (header, comments, blank lines).
  final int skippedLines;

  /// Name of the column used as the ECG, when the file had a header.
  final String? columnName;

  /// Detected time axis; it is reported but never analyzed.
  final String? timeColumn;
}

const List<String> _timeHints = <String>[
  'time',
  'sec',
  'timestamp',
  'index',
  'idx',
  'sample',
];

double? _toDouble(String field) {
  final cleaned = field.trim().replaceAll('"', '').replaceAll("'", '');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite) return null;
  return value;
}

String _delimiter(List<String> lines) {
  var best = '';
  var bestCount = 0;
  for (final separator in const <String>[',', ';', '\t']) {
    var count = 0;
    for (var i = 0; i < lines.length && i < 20; i++) {
      count += separator.allMatches(lines[i]).length;
    }
    if (count > bestCount) {
      bestCount = count;
      best = separator;
    }
  }
  return best;
}

List<String> _split(String line, String separator) {
  if (separator.isEmpty) return <String>[line.trim()];
  return <String>[for (final field in line.split(separator)) field.trim()];
}

/// True for a header that says 'time', or a strictly increasing, even column.
bool _looksLikeTime(String name, List<double?> column) {
  final lowered = name.trim().toLowerCase();
  // A single "t" must match exactly: "voltage" or "rate" contain it.
  if (lowered == 't') return true;
  for (final hint in _timeHints) {
    if (lowered.contains(hint)) return true;
  }
  if (column.length < 2) return false;
  final values = <double>[];
  for (final value in column) {
    if (value == null) return false;
    values.add(value);
  }
  final diffs = <double>[];
  for (var i = 1; i < values.length; i++) {
    final diff = values[i] - values[i - 1];
    if (diff <= 0) return false;
    diffs.add(diff);
  }
  final step = median(diffs);
  if (step <= 0) return false;
  // Writers round the time axis, so allow a few percent of jitter.
  for (final diff in diffs) {
    if ((diff - step).abs() > 0.05 * step) return false;
  }
  return true;
}

/// Parse a signal file.
///
/// Accepts one value per line or comma/semicolon/tab separated columns. Comment
/// lines, blank lines and a text header are skipped, and the time column of a
/// two-column (time, ecg) file is dropped instead of being analyzed.
ParsedSignal parseSignalText(String text) {
  final lines = <String>[];
  var skipped = 0;
  for (final rawLine in const LineSplitter().convert(text)) {
    final line = rawLine.trim().replaceAll('\ufeff', '');
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
      skipped++;
      continue;
    }
    lines.add(line);
  }
  if (lines.isEmpty) {
    return ParsedSignal(values: const <double>[], skippedLines: skipped);
  }

  final separator = _delimiter(lines);
  final header = _split(lines.first, separator);
  final hasHeader = header.any((field) => _toDouble(field) == null);
  final names = hasHeader ? header : const <String>[];

  final rows = <List<String>>[];
  for (var i = hasHeader ? 1 : 0; i < lines.length; i++) {
    final fields = _split(lines[i], separator);
    if (fields.isEmpty) {
      skipped++;
      continue;
    }
    rows.add(fields);
  }
  if (rows.isEmpty) {
    return ParsedSignal(values: const <double>[], skippedLines: skipped);
  }

  final width = names.isNotEmpty ? names.length : rows.first.length;
  if (width == 0) {
    return ParsedSignal(values: const <double>[], skippedLines: skipped);
  }

  final columns = <List<double?>>[
    for (var c = 0; c < width; c++)
      <double?>[
        for (final row in rows) c < row.length ? _toDouble(row[c]) : null,
      ],
  ];

  final usable = <int>[
    for (var c = 0; c < width; c++)
      if (columns[c].any((value) => value != null)) c,
  ];
  if (usable.isEmpty) {
    return ParsedSignal(values: const <double>[], skippedLines: skipped);
  }

  int? timeColumn;
  for (final c in usable) {
    final name = names.isNotEmpty && c < names.length ? names[c] : '';
    if (_looksLikeTime(name, columns[c])) {
      timeColumn = c;
      break;
    }
  }
  final candidates = <int>[
    for (final c in usable)
      if (c != timeColumn) c,
  ];
  if (candidates.isEmpty) {
    return ParsedSignal(values: const <double>[], skippedLines: skipped);
  }

  // A missing field becomes NaN on purpose: the pipeline interpolates short
  // gaps and refuses a file that is mostly broken, instead of shifting time.
  final chosen = candidates.first;
  final values = <double>[
    for (final value in columns[chosen]) value ?? double.nan,
  ];

  String? nameOf(int? c) {
    if (c == null || names.isEmpty || c >= names.length) return null;
    final name = names[c].trim();
    return name.isEmpty ? null : name;
  }

  return ParsedSignal(
    values: values,
    skippedLines: skipped,
    columnName: nameOf(chosen),
    timeColumn: nameOf(timeColumn),
  );
}

/// Parse [text] on a background isolate, so a large file cannot freeze the UI.
Future<ParsedSignal> parseSignalTextAsync(String text) {
  return Isolate.run(() => parseSignalText(text));
}

/// Parse a sampling rate typed by the user.
///
/// Persian (۰-۹) and Arabic-Indic (٠-٩) digits and the Arabic decimal separator
/// are normalized first, because a Persian keyboard produces those.
double? parseSamplingRate(String text) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final buffer = StringBuffer();
  for (final char in text.trim().split('')) {
    final persianIndex = persian.indexOf(char);
    final arabicIndex = arabic.indexOf(char);
    if (persianIndex >= 0) {
      buffer.write(persianIndex);
    } else if (arabicIndex >= 0) {
      buffer.write(arabicIndex);
    } else if (char == '\u066b') {
      buffer.write('.');
    } else if (char == '\u066c') {
      // Arabic thousands separator: drop it.
      continue;
    } else {
      buffer.write(char);
    }
  }
  return double.tryParse(buffer.toString());
}

/// Small helper used by the UI to describe a signal.
double signalDurationSeconds(List<double> values, double fs) =>
    fs <= 0 ? 0 : values.length / fs;

/// Root-mean-square, used only for a quick sanity readout.
double rms(List<double> values) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final v in values) {
    sum += v * v;
  }
  return math.sqrt(sum / values.length);
}