import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_info_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../auth/presentation/providers/auth_controller.dart';

/// Branded splash screen shown while Firebase initialises and auth resolves.
///
/// Guarantees a minimum 1 200 ms display even if auth resolves faster,
/// then navigates to `/login` or `/` based on auth state.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _barController;
  late final Animation<double> _barAnimation;

  @override
  void initState() {
    super.initState();

    // ── Indeterminate progress-bar shimmer ──────────────────────────
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _barAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _barController, curve: Curves.easeInOut),
    );

    // ── Bootstrap: min delay + auth ────────────────────────────────
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final minDelay = Future.delayed(const Duration(milliseconds: 1200));

    // Wait until auth leaves the AuthInitial state.
    final authReady = Completer<void>();
    final sub = ref.listenManual<AuthState>(
      authControllerProvider,
      (_, next) {
        if (next is! AuthInitial && !authReady.isCompleted) {
          authReady.complete();
        }
      },
    );
    // Already resolved?
    if (ref.read(authControllerProvider) is! AuthInitial &&
        !authReady.isCompleted) {
      authReady.complete();
    }

    await Future.wait([minDelay, authReady.future]);
    sub.close();

    if (!mounted) return;

    final authState = ref.read(authControllerProvider);
    final route = authState is AuthAuthenticated ? '/' : '/login';
    ref.read(routerProvider).go(route);
  }

  @override
  void dispose() {
    _barController.dispose();
    super.dispose();
  }

  // ── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final version = ref.watch(appVersionProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // 1 ─ Radial-gradient ornament (centred ~50 % x, ~30 % y)
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, -0.4),
                  radius: 0.55,
                  colors: [
                    Color(0x12C8A36B), // rgba(200,163,107, ~0.07)
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 2 ─ Brand column (shifted ~10 % above centre)
          Align(
            alignment: const Alignment(0.0, -0.18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo — 65 % of screen width
                Image.asset(
                  'assets/logo-full-trans.png',
                  width: screenWidth * 0.65,
                  fit: BoxFit.contain,
                ),

                const SizedBox(height: 24),

                // Gold horizontal rule
                Container(width: 40, height: 2, color: AppColors.accent),

                const SizedBox(height: 18),

                // Subtitle
                const Text(
                  'سير اعتماد المستندات',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
          ),

          // 3 ─ Indeterminate progress bar (130 dp from bottom)
          Positioned(
            bottom: 130,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 120,
                height: 4,
                child: AnimatedBuilder(
                  animation: _barAnimation,
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size(120, 4),
                      painter: _ShimmerBarPainter(
                        progress: _barAnimation.value,
                        trackColor: AppColors.accentSoft,
                        fillColor: AppColors.accent,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // 4 ─ Version caption (100 dp from bottom)
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Text(
              'v $version · 2025',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                color: AppColors.text3,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sliding shimmer bar painter ────────────────────────────────────────────

class _ShimmerBarPainter extends CustomPainter {
  const _ShimmerBarPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
  });

  final double progress;
  final Color trackColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);

    // Full-width track
    canvas.drawRRect(
      RRect.fromLTRBR(0, 0, size.width, size.height, r),
      Paint()..color = trackColor,
    );

    // Sliding fill (~35 % wide)
    const fillRatio = 0.35;
    final fillW = size.width * fillRatio;
    final left = (size.width - fillW) * progress;

    canvas.drawRRect(
      RRect.fromLTRBR(left, 0, left + fillW, size.height, r),
      Paint()..color = fillColor,
    );
  }

  @override
  bool shouldRepaint(_ShimmerBarPainter old) => old.progress != progress;
}