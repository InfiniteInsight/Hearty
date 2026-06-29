import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: '822563687817-ilgg7pf13akhprkvh5i8t6oonmdbrlgh.apps.googleusercontent.com',
      );
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in flow
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (!mounted) return;
      if (idToken == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Google sign-in failed: could not retrieve ID token.';
        });
        return;
      }

      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );

      // GoRouter will automatically redirect to /onboarding or /home
      // via refreshListenable when auth state changes.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sign-in failed: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text.rich(
                      const TextSpan(
                        children: [
                          TextSpan(
                            text: 'Heart',
                            style: TextStyle(color: Aurora.textPrimary),
                          ),
                          TextSpan(
                            text: 'y',
                            style: TextStyle(color: Aurora.accentGreen),
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your food & symptom journal',
                      style: TextStyle(
                        color: Aurora.textMuted,
                        fontSize: 15,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: _isLoading ? null : Aurora.fab,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _signInWithGoogle,
                          icon: _isLoading
                              ? const SizedBox.shrink()
                              : const Icon(
                                  Icons.g_mobiledata,
                                  color: Color(0xFF052E20),
                                  size: 28,
                                ),
                          label: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF052E20),
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    color: Color(0xFF052E20),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            disabledBackgroundColor: Aurora.glassFill,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Aurora.accentRed,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
