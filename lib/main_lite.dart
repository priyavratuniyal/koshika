import 'main.dart';

/// Entry point for the lite flavor — no AI, no model downloads.
Future<void> main() async => appMain(aiEnabled: false);
