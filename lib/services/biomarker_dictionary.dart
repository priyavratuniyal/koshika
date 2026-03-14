import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:string_similarity/string_similarity.dart';

/// Represents a single biomarker definition from the dictionary.
class BiomarkerDefinition {
  final String key;
  final List<String> aliases;
  final String displayName;
  final String category;
  final String unit;
  final double? refLowMale;
  final double? refHighMale;
  final double? refLowFemale;
  final double? refHighFemale;
  final String loincCode;

  const BiomarkerDefinition({
    required this.key,
    required this.aliases,
    required this.displayName,
    required this.category,
    required this.unit,
    this.refLowMale,
    this.refHighMale,
    this.refLowFemale,
    this.refHighFemale,
    required this.loincCode,
  });

  factory BiomarkerDefinition.fromJson(Map<String, dynamic> json) {
    final refMale = json['refRangeMale'] as Map<String, dynamic>?;
    final refFemale = json['refRangeFemale'] as Map<String, dynamic>?;

    return BiomarkerDefinition(
      key: json['key'] as String,
      aliases: (json['aliases'] as List).cast<String>(),
      displayName: json['displayName'] as String,
      category: json['category'] as String,
      unit: json['unit'] as String,
      refLowMale: (refMale?['low'] as num?)?.toDouble(),
      refHighMale: (refMale?['high'] as num?)?.toDouble(),
      refLowFemale: (refFemale?['low'] as num?)?.toDouble(),
      refHighFemale: (refFemale?['high'] as num?)?.toDouble(),
      loincCode: json['loincCode'] as String,
    );
  }

  /// Get reference range for a given sex ('M', 'F', or null for male defaults)
  ({double? low, double? high}) getRefRange(String? sex) {
    if (sex == 'F') {
      return (low: refLowFemale, high: refHighFemale);
    }
    return (low: refLowMale, high: refHighMale);
  }
}

/// Match result from the fuzzy matcher.
class BiomarkerMatch {
  final BiomarkerDefinition definition;
  final double score;
  final String matchedAlias;

  const BiomarkerMatch({
    required this.definition,
    required this.score,
    required this.matchedAlias,
  });
}

/// Service for loading and querying the biomarker dictionary.
/// Supports exact matching, alias matching, and fuzzy matching
/// for lab report text that doesn't exactly match our dictionary.
class BiomarkerDictionary {
  final List<BiomarkerDefinition> _definitions = [];

  /// Index from lowercase alias → definition for O(1) exact matching
  final Map<String, BiomarkerDefinition> _aliasIndex = {};

  /// Index from category → definitions
  final Map<String, List<BiomarkerDefinition>> _categoryIndex = {};

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  /// Load the dictionary from the bundled JSON asset.
  Future<void> load() async {
    if (_isLoaded) return;

    final jsonStr = await rootBundle.loadString(
      'assets/data/biomarker_dictionary.json',
    );
    final jsonList = json.decode(jsonStr) as List<dynamic>;

    for (final item in jsonList) {
      final def = BiomarkerDefinition.fromJson(item as Map<String, dynamic>);
      _definitions.add(def);

      // Build alias index (lowercase for case-insensitive matching)
      for (final alias in def.aliases) {
        _aliasIndex[alias.toLowerCase()] = def;
      }
      // Also index by key
      _aliasIndex[def.key.toLowerCase()] = def;
      _aliasIndex[def.displayName.toLowerCase()] = def;

      // Build category index
      _categoryIndex.putIfAbsent(def.category, () => []).add(def);
    }

    _isLoaded = true;
  }

  /// Get all definitions.
  List<BiomarkerDefinition> get all => List.unmodifiable(_definitions);

  /// Get all unique categories.
  List<String> get categories => _categoryIndex.keys.toList();

  /// Get definitions for a specific category.
  List<BiomarkerDefinition> getByCategory(String category) {
    return _categoryIndex[category] ?? [];
  }

  /// Get a definition by its canonical key.
  BiomarkerDefinition? getByKey(String key) {
    return _definitions.where((d) => d.key == key).firstOrNull;
  }

  /// Exact case-insensitive match against aliases.
  BiomarkerDefinition? exactMatch(String testName) {
    return _aliasIndex[testName.toLowerCase().trim()];
  }

  /// Fuzzy match a test name from a lab report against the dictionary.
  /// Returns the best match above [threshold] (default 0.6), or null.
  BiomarkerMatch? fuzzyMatch(String testName, {double threshold = 0.6}) {
    final input = testName.toLowerCase().trim();

    // 1. Try exact match first (O(1))
    final exact = _aliasIndex[input];
    if (exact != null) {
      return BiomarkerMatch(
        definition: exact,
        score: 1.0,
        matchedAlias: testName,
      );
    }

    // 2. Try contains match (check if input contains any alias or vice versa)
    for (final def in _definitions) {
      for (final alias in def.aliases) {
        final aliasLower = alias.toLowerCase();
        if (input.contains(aliasLower) || aliasLower.contains(input)) {
          // Give a high score for substring matches, scaled by length similarity
          final lengthRatio = input.length < aliasLower.length
              ? input.length / aliasLower.length
              : aliasLower.length / input.length;
          final score = 0.8 * lengthRatio;
          if (score >= threshold) {
            return BiomarkerMatch(
              definition: def,
              score: score,
              matchedAlias: alias,
            );
          }
        }
      }
    }

    // 3. Fuzzy match using string similarity (Dice coefficient)
    BiomarkerMatch? bestMatch;
    double bestScore = 0;

    for (final def in _definitions) {
      for (final alias in def.aliases) {
        final score = input.similarityTo(alias.toLowerCase());
        if (score > bestScore && score >= threshold) {
          bestScore = score;
          bestMatch = BiomarkerMatch(
            definition: def,
            score: score,
            matchedAlias: alias,
          );
        }
      }
    }

    return bestMatch;
  }

  /// Match multiple test names at once and return a map of matches.
  /// Useful for batch processing an entire lab report.
  Map<String, BiomarkerMatch?> batchMatch(
    List<String> testNames, {
    double threshold = 0.5,
  }) {
    final results = <String, BiomarkerMatch?>{};
    for (final name in testNames) {
      results[name] = fuzzyMatch(name, threshold: threshold);
    }
    return results;
  }
}
