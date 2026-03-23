import 'package:flutter/material.dart';

import '../models/model_info.dart';
import '../services/objectbox_store.dart';
import '../services/biomarker_dictionary.dart';
import '../services/embedding_service.dart';
import '../services/gemma_service.dart';
import '../services/vector_store_service.dart';
import '../main.dart' as app_main;
import 'onboarding_screen.dart';

/// Animated splash screen shown during app initialization.
///
/// Displays a branded launch experience while ObjectBox, the biomarker
/// dictionary, and the Gemma service are initializing in the background.
/// After initialization, navigates to [OnboardingScreen] or [HomeScreen]
/// based on whether the user has completed onboarding.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize ObjectBox
      app_main.objectbox = await ObjectBoxStore.create();

      // Load biomarker dictionary
      app_main.biomarkerDictionary = BiomarkerDictionary();
      await app_main.biomarkerDictionary.load();

      // Create default patient profile
      app_main.objectbox.getOrCreateDefaultPatient();

      // Initialize Gemma service (checks if model exists on disk — never blocks)
      app_main.gemmaService = GemmaService();
      await app_main.gemmaService.initialize();

      // Initialize embedding + vector store services
      app_main.embeddingService = EmbeddingService();
      await app_main.embeddingService.initialize();

      app_main.vectorStoreService = VectorStoreService(
        app_main.embeddingService,
      );
      await app_main.vectorStoreService.initialize();

      // Kick off model loading in the background if already downloaded.
      // These are unawaited — navigation proceeds immediately, models finish
      // loading while the user is on the home screen.
      if (app_main.gemmaService.currentModelInfo.status == ModelStatus.ready) {
        // ignore: unawaited_futures
        app_main.gemmaService.loadModel();
      }
      if (app_main.embeddingService.currentModelInfo.status ==
          ModelStatus.ready) {
        // ignore: unawaited_futures
        app_main.embeddingService.loadModel();
      }

      // Ensure animation has played for at least 1.5 seconds
      await Future.delayed(const Duration(milliseconds: 1500));

      if (!mounted) return;

      // Check onboarding state and navigate
      final onboardingDone = await OnboardingScreen.isComplete();

      if (!mounted) return;

      if (onboardingDone) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    } catch (e) {
      debugPrint('SplashScreen initialization error: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Something went wrong during startup. Please restart the app.';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(scale: _scaleAnimation, child: child),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primaryContainer,
                ),
                child: Icon(
                  Icons.biotech_rounded,
                  size: 48,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),

              const SizedBox(height: 24),

              // App name
              Text(
                'Koshika',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),

              const SizedBox(height: 4),

              // Hindi subtitle
              Text(
                'कोशिका',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w300,
                ),
              ),

              const SizedBox(height: 8),

              // Tagline
              Text(
                'Your health data, understood.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),

              const SizedBox(height: 40),

              // Loading indicator or error
              if (_errorMessage != null) ...[
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() => _errorMessage = null);
                    _initializeApp();
                  },
                  child: const Text('Retry'),
                ),
              ] else
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
