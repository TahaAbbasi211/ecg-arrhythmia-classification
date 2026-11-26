/// Data layer: loading the bundled model, config and sample records.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../ecg/analyze.dart';
import '../ecg/forest.dart';

/// A built-in demo record.
class SampleRecord {
  const SampleRecord({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.assetPath,
  });

  final String id;
  final String title;
  final String subtitle;
  final String assetPath;
}

const List<SampleRecord> sampleRecords = [
  SampleRecord(
    id: '200',
    title: 'Record 200',
    subtitle: '60 s · several ventricular beats',
    assetPath: 'assets/samples/record_200.csv',
  ),
  SampleRecord(
    id: '100',
    title: 'Record 100',
    subtitle: '60 s · clean normal rhythm',
    assetPath: 'assets/samples/record_100.csv',
  ),
  SampleRecord(
    id: '233',
    title: 'Record 233',
    subtitle: '60 s · mixed rhythm',
    assetPath: 'assets/samples/record_233.csv',
  ),
];

/// Loads the config and forest once and keeps them in memory.
class ModelBundle {
  ModelBundle({required this.config, required this.forest});

  final EcgConfig config;
  final Forest forest;

  EcgAnalyzer get analyzer => EcgAnalyzer(config: config, forest: forest);

  static Future<ModelBundle> load() async {
    final configJson =
        jsonDecode(await rootBundle.loadString('assets/ecg_config.json'))
            as Map<String, dynamic>;
    final forestJson =
        jsonDecode(await rootBundle.loadString('assets/ecg_forest.json'))
            as Map<String, dynamic>;
    return ModelBundle(
      config: EcgConfig.fromJson(configJson),
      forest: Forest.fromJson(forestJson),
    );
  }
}
