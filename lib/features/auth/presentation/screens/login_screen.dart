import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_failure.dart';
import '../../../../core/providers/app_info_provider.dart';
import '../../../../core/storage/token_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  /// Seconds left on a `too_many_attempts` lockout. Null when not locked out.
  int? _lockoutSeconds;
  Timer? _lockoutTimer;

  bool get _isLockedOut => (_lockoutSeconds ?? 0) > 0;

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Runs the lockout down to zero, re-enabling the button when it lifts.
  ///
  /// The backend reports time REMAINING, not the full lockout, so a user who
  /// comes back part-way through a lockout is told what is actually left.
  void _startLockout(int seconds) {
    _lockoutTimer?.cancel();
    setState(() => _lockoutSeconds = seconds);
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = (_lockoutSeconds ?? 0) - 1;
      setState(() => _lockoutSeconds = left > 0 ? left : null);
      if (left <= 0) timer.cancel();
    });
  }

  /// `2:05` above a minute, plain seconds below it.
  static String _formatCountdown(int seconds) {
    if (seconds < 60) return '$seconds ثانية';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (_isLockedOut) return;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(_emailController.text.trim(), _passwordController.text);
      // Router redirect handles navigation.
    } on ApiFailure catch (failure) {
      // Throttled (backend v10). The message is a complete Arabic sentence
      // naming the wait, so it is shown as-is; `retry_after` additionally
      // drives a live countdown and keeps the button disabled meanwhile, so
      // hammering the button cannot spend more of the budget.
      //
      // Deliberately NOT branched on separately: an unknown email and a wrong
      // password. The backend answers those identically — same status, same
      // body, same headers — precisely so the screen cannot tell them apart,
      // and neither should this code.
      if (failure.code == ApiErrorCode.tooManyAttempts) {
        final retryAfter = failure.retryAfter;
        setState(() {
          _errorMessage =
              arabicMessageFor(failure.code, fallback: failure.message);
        });
        if (retryAfter != null && retryAfter > 0) _startLockout(retryAfter);
        return;
      }
      final emailFieldError = failure.firstErrorFor('email');
      setState(() {
        _errorMessage = emailFieldError ?? failure.message;
      });
    } on TokenStorageException {
      // Credentials were fine; the device could not store the session. Say so,
      // because retrying the same password will not help.
      setState(() {
        _errorMessage =
            'تعذر حفظ الجلسة على هذا الجهاز. الرجاء إعادة تشغيل التطبيق '
            'والمحاولة مرة أخرى.';
      });
    } catch (_) {
      setState(() {
        _errorMessage = arabicMessageFor(ApiErrorCode.unknown);
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _errorMessage != null;
    final version = ref.watch(appVersionProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 32),

                    // ── 1. Hero card ──────────────────────────────
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: const Color(0xFFF2E4CC),
                          width: 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x4DC8A36B),
                            blurRadius: 22,
                            offset: Offset(0, 6),
                          ),
                          BoxShadow(
                            color: Color(0x2EC8A36B),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/logo-symbol-gold.png',
                          width: 64,
                          height: 64,
                        ),
                      ),
                    ),

                    // ── 2. 18dp gap ──────────────────────────────
                    const SizedBox(height: 18),

                    // ── 3. Title ──────────────────────────────────
                    const Text(
                      'سير اعتماد المستندات',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1B2A41),
                      ),
                      textAlign: TextAlign.center,
                    ),

                    // ── 4. 10dp gap ──────────────────────────────
                    const SizedBox(height: 10),

                    // ── 5. Gold rule ──────────────────────────────
                    Container(
                      width: 28,
                      height: 2,
                      color: const Color(0xFFC8A36B),
                    ),

                    // ── 6. 12dp gap ──────────────────────────────
                    const SizedBox(height: 12),

                    // ── 7. Subtitle ───────────────────────────────
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: const Text(
                        'أهلاً بعودتك. يرجى تسجيل الدخول للمتابعة.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF6B7591),
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    // ── 8. 30dp gap ──────────────────────────────
                    const SizedBox(height: 30),

                    // ── Form ─────────────────────────────────────
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── 9. Email field ─────────────────────
                          _FieldLabel(text: 'البريد الإلكتروني'),
                          const SizedBox(height: 6),
                          _AlraqiTextField(
                            controller: _emailController,
                            hint: 'name@al-raqi.sa',
                            prefixIcon: Icons.mail_outline,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            enabled: !_isSubmitting,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'الرجاء إدخال البريد الإلكتروني';
                              }
                              if (!value.contains('@')) {
                                return 'بريد إلكتروني غير صحيح';
                              }
                              return null;
                            },
                          ),

                          // ── 10. 14dp gap ───────────────────────
                          const SizedBox(height: 14),

                          // ── 11. Password field ─────────────────
                          _FieldLabel(text: 'كلمة المرور'),
                          const SizedBox(height: 6),
                          _AlraqiTextField(
                            controller: _passwordController,
                            hint: '••••••••',
                            prefixIcon: Icons.lock_outline,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            enabled: !_isSubmitting,
                            hasError: hasError,
                            onFieldSubmitted: (_) => _submit(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 18,
                                color: const Color(0xFF6B7591),
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'الرجاء إدخال كلمة المرور';
                              }
                              return null;
                            },
                          ),

                          // ── 12. Error banner ───────────────────
                          if (hasError) ...[
                            const SizedBox(height: 10),
                            _AlraqiErrorBanner(message: _errorMessage!),
                          ],

                          // ── 13. 8dp gap ────────────────────────
                          const SizedBox(height: 8),

                          // ── 14. Forgot password ────────────────
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton(
                              onPressed: () {
                                _showForgotPasswordDialog(context);
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'نسيت كلمة المرور؟',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF224167),
                                ),
                              ),
                            ),
                          ),

                          // ── 15. 22dp gap ───────────────────────
                          const SizedBox(height: 22),

                          // ── 16. Primary button ─────────────────
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: (_isSubmitting || _isLockedOut)
                                  ? null
                                  : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF224167),
                                disabledBackgroundColor:
                                    const Color(0xFF224167),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : _isLockedOut
                                      // Live countdown, so the wait is
                                      // visible rather than a dead button.
                                      ? Text(
                                          'إعادة المحاولة بعد '
                                          '${_formatCountdown(_lockoutSeconds!)}',
                                          key: const Key(
                                              'login-lockout-countdown'),
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'تسجيل الدخول',
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Icon(
                                              Icons.arrow_forward,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                          ],
                                        ),
                            ),
                          ),

                          // ── 17. 18dp gap ───────────────────────
                          const SizedBox(height: 18),

                          // ── 18. Terms text ─────────────────────
                          const Text(
                            'بدخولك توافق على سياسة الاستخدام الداخلية لشركة الراقي',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF9099AD),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    // ── 19. Spacer ────────────────────────────────
                    const SizedBox(height: 48),

                    // ── 20. Version footer ────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Text(
                        'AL-RAQI · v $version',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF9099AD),
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showForgotPasswordDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'نسيت كلمة المرور؟',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF224167),
              ),
            ),
            content: const Text(
              'يرجى التواصل مع مدير القسم التقني محمد هوى على الرقم:\n'
              '+963958244652',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.6,
                color: Color(0xFF224167),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'حسناً',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF224167),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF6B7591),
      ),
    );
  }
}

class _AlraqiTextField extends StatefulWidget {
  const _AlraqiTextField({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.suffixIcon,
    this.enabled = true,
    this.hasError = false,
    this.onFieldSubmitted,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final Widget? suffixIcon;
  final bool enabled;
  final bool hasError;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  State<_AlraqiTextField> createState() => _AlraqiTextFieldState();
}

class _AlraqiTextFieldState extends State<_AlraqiTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color borderColor = widget.hasError
        ? const Color(0xFFB3261E)
        : _focused
            ? const Color(0xFF224167)
            : const Color(0xFFE4E6EE);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: _focused && !widget.hasError
            ? const [
                BoxShadow(
                  color: Color(0x14224167), // rgba(34,65,103,0.08)
                  blurRadius: 0,
                  spreadRadius: 4,
                ),
              ]
            : null,
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        autofillHints: widget.autofillHints,
        enabled: widget.enabled,
        onFieldSubmitted: widget.onFieldSubmitted,
        validator: widget.validator,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Color(0xFF1B2A41),
        ),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF9099AD),
          ),
          prefixIcon: Padding(
            padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
            child: Icon(
              widget.prefixIcon,
              size: 18,
              color: const Color(0xFF6B7591),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          suffixIcon: widget.suffixIcon,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: borderColor,
              width: 1.5,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: borderColor,
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: borderColor,
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFB3261E),
              width: 1.5,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFB3261E),
              width: 1.5,
            ),
          ),
          errorStyle: const TextStyle(fontSize: 0, height: 0),
        ),
      ),
    );
  }
}

class _AlraqiErrorBanner extends StatelessWidget {
  const _AlraqiErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBE7E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFF4C2BF),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.only(end: 8, top: 2),
            child: Icon(
              Icons.error_outline,
              size: 18,
              color: Color(0xFFB3261E),
            ),
          ),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Color(0xFF6E1410),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
