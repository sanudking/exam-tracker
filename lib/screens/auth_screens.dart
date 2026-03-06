import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import 'main_dashboard.dart';
import 'exam_tracker_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    _progressController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2600),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _goNext();
          }
        });
    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _goNext() {
    if (!mounted || _didNavigate) return;
    _didNavigate = true;
    final hasSession = supabase.auth.currentSession != null;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            hasSession ? const MainDashboard() : const OnboardingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryBlue,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'ExamTracker',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your study companion',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              AnimatedBuilder(
                animation: _progressController,
                builder: (context, _) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _progressController.value,
                      minHeight: 5,
                      backgroundColor: Colors.white.withValues(alpha: 0.24),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _index = 0;

  final List<_OnboardingData> _pages = const [
    _OnboardingData(
      art: _OnboardingArtType.track,
      title: 'Track Exams',
      subtitle:
          'Keep all your important exam dates and schedules in one organized place.',
    ),
    _OnboardingData(
      art: _OnboardingArtType.notify,
      title: 'Get Notified',
      subtitle:
          "Never miss a test. Customizable reminders ensure you're always prepared.",
    ),
    _OnboardingData(
      art: _OnboardingArtType.plan,
      title: 'Start Planning',
      subtitle:
          'Organize your syllabus and notes for every subject efficiently.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToAuthChoice() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthChoiceScreen()),
    );
  }

  void _next() {
    if (_index == _pages.length - 1) {
      _goToAuthChoice();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (_, pageIndex) {
                    final page = _pages[pageIndex];
                    return Column(
                      children: [
                        Container(
                          height: 310,
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: kSurfaceCard,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: _OnboardingArt(type: page.art),
                        ),
                        const SizedBox(height: 34),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: kDarkText,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          page.subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 1.35,
                            color: kMutedText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (!isLast)
                Row(
                  children: [
                    TextButton(
                      onPressed: _goToAuthChoice,
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 20,
                          color: kMutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: List.generate(
                        _pages.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _index ? 26 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? kPrimaryBlue
                                : const Color(0xFFCFD8E3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _next,
                      child: const Text(
                        'Next',
                        style: TextStyle(
                          fontSize: 20,
                          color: kPrimaryBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _goToAuthChoice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: const Text(
                      'Get Started',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingData {
  final _OnboardingArtType art;
  final String title;
  final String subtitle;

  const _OnboardingData({
    required this.art,
    required this.title,
    required this.subtitle,
  });
}

enum _OnboardingArtType { track, notify, plan }

class _OnboardingArt extends StatelessWidget {
  const _OnboardingArt({required this.type});

  final _OnboardingArtType type;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEFF6FF), Color(0xFFD8E8FF)],
              ),
            ),
          ),
          Positioned(
            top: -36,
            right: -26,
            child: _orb(128, const Color(0xFF9CC3FF), 0.32),
          ),
          Positioned(
            bottom: -52,
            left: -34,
            child: _orb(150, const Color(0xFF80AEFF), 0.24),
          ),
          Positioned(
            top: 26,
            left: 22,
            right: 22,
            bottom: 22,
            child: _GlassShell(child: _artContent(type)),
          ),
        ],
      ),
    );
  }

  static Widget _orb(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
      ),
    );
  }

  static Widget _artContent(_OnboardingArtType type) {
    switch (type) {
      case _OnboardingArtType.track:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 170,
              height: 142,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: Colors.white.withValues(alpha: 0.48),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: const Color(0xFFD8E8FF),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    height: 1.5,
                    color: const Color(0xFFD0E2FF),
                  ),
                  const SizedBox(height: 20),
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 46,
                    color: Color(0xFF4F86EA),
                  ),
                ],
              ),
            ),
          ],
        );
      case _OnboardingArtType.notify:
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 165,
                height: 165,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.42),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.65),
                    width: 1.5,
                  ),
                ),
              ),
              const Icon(
                Icons.notifications_active_rounded,
                size: 86,
                color: Color(0xFF4E84E8),
              ),
              Positioned(
                left: 16,
                right: 16,
                child: Container(height: 2, color: const Color(0xFFBCD4FA)),
              ),
            ],
          ),
        );
      case _OnboardingArtType.plan:
        return Center(
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white.withValues(alpha: 0.52),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                _ChecklistRow(),
                SizedBox(height: 10),
                _ChecklistRow(),
                SizedBox(height: 10),
                _ChecklistRow(),
              ],
            ),
          ),
        );
    }
  }
}

class _GlassShell extends StatelessWidget {
  const _GlassShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: Colors.white.withValues(alpha: 0.28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.56),
              width: 1.2,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, size: 20, color: Color(0xFF4F86EA)),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: const Color(0xFFD4E5FF),
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _inputDecoration(String hint) {
  return const InputDecoration().copyWith(
    hintText: hint,
    border: const UnderlineInputBorder(borderSide: BorderSide(color: kBorder)),
    enabledBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: kBorder),
    ),
    focusedBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: kPrimaryBlue, width: 2),
    ),
    hintStyle: const TextStyle(
      color: Color(0xFF9BA8BA),
      fontSize: 20,
      fontWeight: FontWeight.w500,
    ),
    contentPadding: const EdgeInsets.only(bottom: 10),
  );
}

class AuthChoiceScreen extends StatelessWidget {
  const AuthChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0xFFE9F2FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: kPrimaryBlue,
                  size: 40,
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                "Let's Get Started",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kDarkText,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose one option to continue',
                style: TextStyle(
                  color: kMutedText,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text(
                    'I already have an account',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kPrimaryBlue,
                    side: const BorderSide(color: kPrimaryBlue, width: 1.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text(
                    'Register',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainDashboard()),
        (_) => false,
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Login failed. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0xFFE9F2FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: kPrimaryBlue,
                  size: 40,
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'Login',
                style: TextStyle(
                  color: kDarkText,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 54),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'EMAIL',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF627389),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('you@example.com'),
              ),
              const SizedBox(height: 30),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'PASSWORD',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF627389),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: _inputDecoration('••••••••'),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ForgotPasswordScreen(
                                initialEmail: _emailController.text.trim(),
                              ),
                            ),
                          );
                        },
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(
                      color: kPrimaryBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.3,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailController;
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSending = false;
  bool _isUpdating = false;
  bool _hasSentCode = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendResetCode() async {
    if (_isSending) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Enter your registered email first.'),
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      await supabase.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() => _hasSentCode = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text(
            'If this email exists, a reset code was sent to that inbox.',
          ),
        ),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Could not send reset code. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _verifyCodeAndUpdatePassword() async {
    if (_isUpdating) return;
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (email.isEmpty || otp.isEmpty || newPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Email, OTP and new password are required.'),
        ),
      );
      return;
    }
    if (otp.length < 6 || otp.length > 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Enter the OTP code from email.'),
        ),
      );
      return;
    }
    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Password must be at least 6 characters long.'),
        ),
      );
      return;
    }
    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Passwords do not match.'),
        ),
      );
      return;
    }

    setState(() => _isUpdating = true);
    try {
      await supabase.auth.verifyOTP(
        type: OtpType.recovery,
        email: email,
        token: otp,
      );

      await supabase.auth.updateUser(UserAttributes(password: newPassword));
      await supabase.auth.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Password reset successful. Please login again.'),
        ),
      );
      Navigator.of(context).pop();
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Could not reset password. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0xFFE9F2FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_reset_rounded,
                  color: kPrimaryBlue,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Reset Password',
                style: TextStyle(
                  color: kDarkText,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _hasSentCode
                    ? 'Enter the code from email and set a new password.'
                    : 'Enter your email and we will send a reset code.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kMutedText,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 42),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'EMAIL',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF627389),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('you@example.com'),
              ),
              if (_hasSentCode) ...[
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'OTP CODE',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF627389),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  decoration: _inputDecoration('OTP code'),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'NEW PASSWORD',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF627389),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: _inputDecoration('At least 6 characters'),
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'CONFIRM PASSWORD',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF627389),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: _inputDecoration('Re-enter password'),
                ),
              ],
              const SizedBox(height: 34),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSending || _isUpdating
                      ? null
                      : _hasSentCode
                      ? _verifyCodeAndUpdatePassword
                      : _sendResetCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: _isSending || _isUpdating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.3,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _hasSentCode
                              ? 'Verify Code & Update'
                              : 'Send Reset Code',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              if (_hasSentCode) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _isSending || _isUpdating ? null : _sendResetCode,
                  child: const Text(
                    'Resend code',
                    style: TextStyle(
                      color: kPrimaryBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_isLoading) return;
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Name, email and password are required.'),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: {'name': _nameController.text.trim()},
      );
      if (!mounted) return;
      if (response.session == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text(
              'Registration complete. Check your email for verification, then login.',
            ),
          ),
        );
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ExamTrackerPage()),
          (_) => false,
        );
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Registration failed. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0xFFE9F2FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: kPrimaryBlue,
                  size: 40,
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'Create Account',
                style: TextStyle(
                  color: kDarkText,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 54),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'NAME',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF627389),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                decoration: _inputDecoration('Your name'),
              ),
              const SizedBox(height: 30),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'EMAIL',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF627389),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('you@example.com'),
              ),
              const SizedBox(height: 30),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'PASSWORD',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF627389),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: _inputDecoration('••••••••'),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.3,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Register',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
