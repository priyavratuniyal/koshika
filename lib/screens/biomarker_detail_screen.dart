import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/models.dart';
import '../widgets/flag_badge.dart';
import '../widgets/biomarker_trend_chart.dart';
import '../widgets/reference_range_gauge.dart';

class BiomarkerDetailScreen extends StatefulWidget {
  final String biomarkerKey;

  const BiomarkerDetailScreen({super.key, required this.biomarkerKey});

  @override
  State<BiomarkerDetailScreen> createState() => _BiomarkerDetailScreenState();
}

class _BiomarkerDetailScreenState extends State<BiomarkerDetailScreen> {
  late List<BiomarkerResult> history;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    try {
      history = objectbox.getHistoryForBiomarker(widget.biomarkerKey);
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (history.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Biomarker Details')),
        body: const Center(
          child: Text('No data available for this biomarker.'),
        ),
      );
    }

    // The most recent result is the first in the list (since it's ordered descending by date)
    final latestResult = history.first;
    final hasNumericValues = history.any((r) => r.value != null);

    return Scaffold(
      appBar: AppBar(
        title: Text(latestResult.displayName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          latestResult.displayName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (latestResult.category != null)
                        Chip(
                          label: Text(
                            latestResult.category!,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: theme.colorScheme.primaryContainer,
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            latestResult.formattedValue,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (latestResult.unit != null)
                            Text(
                              latestResult.unit!,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      FlagBadge(flag: latestResult.flag),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                  ReferenceRangeGauge(
                    value: latestResult.value,
                    refLow: latestResult.refLow,
                    refHigh: latestResult.refHigh,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reference Range: ${latestResult.formattedRefRange}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (latestResult.loincCode != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'LOINC: ${latestResult.loincCode}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Trend Chart Section
          Row(
            children: [
              Text(
                'Trend',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              if (!hasNumericValues)
                Expanded(
                  child: Text(
                    '(No numeric data to chart)',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (hasNumericValues)
            BiomarkerTrendChart(history: history),
          
          if (hasNumericValues)
            const SizedBox(height: 24),

          // History List
          Text(
            'History',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final result = history[index];
                final report = result.report.target;
                
                return ListTile(
                  title: Row(
                    children: [
                      Text(
                        '${result.formattedValue} ${result.unit ?? ""}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      FlagBadge(flag: result.flag),
                    ],
                  ),
                  subtitle: Text(
                    '${DateFormat.yMMMd().format(result.testDate)} • ${report?.labName ?? "Unknown Lab"}',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
