/// File picking and bundled-sample loading.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'analysis_worker.dart';
import 'model_bundle.dart';
import 'signal_parser.dart';

/// Refuse files larger than this: 20 MB is about 90 minutes at 360 Hz, and the
/// whole file is decoded into memory.
const int maxSignalFileBytes = 20 * 1024 * 1024;

/// A problem with the picked file that the user can act on.
class SignalFileException implements Exception {
  const SignalFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A picked text file.
class PickedSignal {
  PickedSignal({required this.name, required this.text});

  final String name;
  final String text;
}

/// Decode raw bytes, tolerating a UTF-8 BOM and legacy single-byte encodings.
String decodeSignalBytes(Uint8List bytes) {
  if (bytes.isEmpty) throw const SignalFileException('The file is empty.');
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Open the system file picker and read the chosen file as text.
///
/// Returns null when the user cancels.
Future<PickedSignal?> pickSignalFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['csv', 'txt'],
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final limitMb = maxSignalFileBytes ~/ (1024 * 1024);
  if (bytes.length > maxSignalFileBytes) {
    throw SignalFileException(
      'That file is larger than $limitMb MB. Split it into shorter records.',
    );
  }
  // Decoding runs in an isolate: a big file must not freeze the first frame.
  final text = await Isolate.run(() => decodeSignalBytes(bytes));
  return PickedSignal(name: file.name, text: text);
}

/// Read a bundled demo record and return its samples.
///
/// Parsing runs in an isolate; only the asset read touches the platform channel.
Future<List<double>> loadSampleValues(SampleRecord sample) async {
  final text = await rootBundle.loadString(sample.assetPath);
  return Isolate.run(() => parseSignalText(text).values);
}

String? _configJson;
String? _modelJson;

/// Run the pipeline off the UI thread on [raw] sampled at [sourceFs].
Future<AnalysisPayload> runAnalysis({
  required List<double> raw,
  required double sourceFs,
}) async {
  _configJson ??= await rootBundle.loadString('assets/ecg_config.json');
  _modelJson ??= await rootBundle.loadString('assets/ecg_model_v3.json');
  return analyzeInIsolate(
    raw: raw,
    sourceFs: sourceFs,
    configJson: _configJson!,
    modelJson: _modelJson!,
  );
}