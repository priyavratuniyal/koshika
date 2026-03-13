import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'services/objectbox_store.dart';
import 'services/biomarker_dictionary.dart';
import 'services/pdf_import_service.dart';
import 'services/pdf_text_extractor.dart';
import 'services/lab_report_parser.dart';
import 'screens/report_detail_screen.dart';

/// Global references — initialized in main() before runApp.
late final ObjectBoxStore objectbox;
late final BiomarkerDictionary biomarkerDictionary;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize ObjectBox
  objectbox = await ObjectBoxStore.create();

  // Load biomarker dictionary
  biomarkerDictionary = BiomarkerDictionary();
  await biomarkerDictionary.load();

  // Create default patient profile
  objectbox.getOrCreateDefaultPatient();

  runApp(const KoshikaApp());
}

class KoshikaApp extends StatelessWidget {
  const KoshikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Koshika',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Health-themed teal/blue palette
    const seed = Color(0xFF0D9488); // Teal-600

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: isDark ? colorScheme.surface : colorScheme.primary,
        foregroundColor: isDark ? colorScheme.onSurface : colorScheme.onPrimary,
      ),
      cardTheme: CardThemeData(
        elevation: isDark ? 1 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Main screen with bottom navigation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  Widget _buildCurrentScreen() {
    switch (_currentIndex) {
      case 0: return const DashboardPlaceholder();
      case 1: return const ReportsPlaceholder();
      case 2: return const ChatPlaceholder();
      default: return const DashboardPlaceholder();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildCurrentScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Chat',
          ),
        ],
      ),
    );
  }
}

// ─── Placeholder screens (will be replaced with real implementations) ───

class DashboardPlaceholder extends StatelessWidget {
  const DashboardPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latestResults = objectbox.getLatestResults();
    final outOfRange = objectbox.getOutOfRangeCount();
    final categories = biomarkerDictionary.categories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Koshika'),
      ),
      body: latestResults.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.biotech_outlined,
                      size: 80,
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No lab reports yet',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Import a lab report PDF from the Reports tab to get started.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Summary card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${latestResults.length} Biomarkers',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              outOfRange > 0
                                  ? '$outOfRange out of range'
                                  : 'All within range ✓',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: outOfRange > 0
                                    ? theme.colorScheme.error
                                    : Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Category cards
                ...categories.map((cat) {
                  final catResults = latestResults.values
                      .where((r) => r.category == cat)
                      .toList();
                  if (catResults.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cat,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const Divider(),
                            ...catResults.map((r) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(r.displayName),
                                  ),
                                  Text(
                                    '${r.formattedValue} ${r.unit ?? ""}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: _flagColor(r.flagIndex, theme),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Color _flagColor(int flagIndex, ThemeData theme) {
    switch (flagIndex) {
      case 0: return Colors.green;    // normal
      case 1: return Colors.orange;   // low
      case 2: return Colors.red;      // high
      case 3: return Colors.red[900]!; // critical
      default: return theme.colorScheme.onSurface;
    }
  }
}

class ReportsPlaceholder extends StatefulWidget {
  const ReportsPlaceholder({super.key});

  @override
  State<ReportsPlaceholder> createState() => _ReportsPlaceholderState();
}

class _ReportsPlaceholderState extends State<ReportsPlaceholder> {
  bool _isImporting = false;

  Future<void> _importPdf() async {
    if (_isImporting) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.single.path == null) return;
      
      final String sourcePath = result.files.single.path!;
      
      setState(() {
        _isImporting = true;
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 24),
                Text('Importing lab report...'),
              ],
            ),
          ),
        );
      }

      final File sourceFile = File(sourcePath);
      final Directory appDocsDir = await getApplicationDocumentsDirectory();
      final String destFileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourcePath)}';
      final String destPath = p.join(appDocsDir.path, destFileName);
      
      await sourceFile.copy(destPath);

      final extractor = PdfTextExtractorService();
      final parser = LabReportParser();
      final service = PdfImportService(extractor, parser, biomarkerDictionary, objectbox);
      
      final importResult = await service.importPdf(destPath);

      setState(() {
        _isImporting = false;
      });

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
      }

      if (mounted) {
        if (importResult.success) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Imported ${importResult.successfulMatches} biomarkers')),
           );
           
           // Navigate to report details
           if (importResult.report != null) {
              Navigator.of(context).push(MaterialPageRoute(
                 builder: (context) => ReportDetailScreen(reportId: importResult.report!.id),
              )).then((_) {
                 setState(() {}); // refresh reports list
              });
           } else {
             setState(() {});
           }
        } else {
           showDialog(
             context: context,
             builder: (context) => AlertDialog(
               title: const Text('Import Failed'),
               content: Text(importResult.errorMessage ?? 'Unknown error'),
               actions: [
                 TextButton(
                   onPressed: () => Navigator.of(context).pop(),
                   child: const Text('OK'),
                 ),
               ],
             ),
           );
        }
      }
    } catch (e) {
       setState(() { _isImporting = false; });
       if (mounted) {
           if (Navigator.canPop(context)) Navigator.of(context).pop();
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error: $e')),
           );
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reports = objectbox.getAllReports();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isImporting ? null : _importPdf,
        icon: _isImporting ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
        label: Text(_isImporting ? 'Importing...' : 'Import PDF'),
      ),
      body: reports.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.upload_file_outlined,
                      size: 80,
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No reports imported',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the button below to import your first lab report PDF.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                return Card(
                  child: ListTile(
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                         builder: (context) => ReportDetailScreen(reportId: report.id),
                      ));
                    },
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.description,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(report.labName ?? report.originalFileName ?? 'Lab Report'),
                    subtitle: Text(
                      '${report.reportDate.day}/${report.reportDate.month}/${report.reportDate.year}'
                      ' • ${report.extractedCount} biomarkers',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              },
            ),
    );
  }
}

class ChatPlaceholder extends StatelessWidget {
  const ChatPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 80,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 24),
              Text(
                'AI Assistant',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Download an on-device AI model to chat about your health data privately. Coming soon.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: null,
                child: const Text('Download AI Model'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
