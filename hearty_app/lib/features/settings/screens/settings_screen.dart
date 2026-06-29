import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
import '../../../core/auth/auth_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // Per-category gradients (Aurora, 315° linear — bottomRight → topLeft).
  static const LinearGradient _accountGradient = LinearGradient(
    begin: Alignment.bottomRight,
    end: Alignment.topLeft,
    colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
  );
  static const LinearGradient _notificationsGradient = LinearGradient(
    begin: Alignment.bottomRight,
    end: Alignment.topLeft,
    colors: [Color(0xFFFFBC00), Color(0xFFFF0058)],
  );
  static const LinearGradient _dictationGradient = LinearGradient(
    begin: Alignment.bottomRight,
    end: Alignment.topLeft,
    colors: [Color(0xFF34D399), Color(0xFF00D0FF)],
  );
  static const LinearGradient _wakeWordGradient = LinearGradient(
    begin: Alignment.bottomRight,
    end: Alignment.topLeft,
    colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6)],
  );
  static const LinearGradient _conversationGradient = LinearGradient(
    begin: Alignment.bottomRight,
    end: Alignment.topLeft,
    colors: [Color(0xFF03A9F4), Color(0xFFFF0058)],
  );
  static const LinearGradient _healthGradient = LinearGradient(
    begin: Alignment.bottomRight,
    end: Alignment.topLeft,
    colors: [Color(0xFF4DFF03), Color(0xFF00D0FF)],
  );
  static const LinearGradient _neutralGradient = LinearGradient(
    begin: Alignment.bottomRight,
    end: Alignment.topLeft,
    colors: [Color(0xFF64748B), Color(0xFF334155)],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);

    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.only(top: 8),
            children: [
              // Account
              _SettingsRow(
                icon: Icons.account_circle,
                gradient: _accountGradient,
                title: 'Account',
                subtitle: currentUser?.email ?? '',
              ),
              // Sign Out (red-tinted)
              _SettingsRow(
                icon: Icons.logout,
                gradient: const LinearGradient(
                  begin: Alignment.bottomRight,
                  end: Alignment.topLeft,
                  colors: [Aurora.accentRed, Aurora.accentRed],
                ),
                title: 'Sign Out',
                titleColor: Aurora.accentRed,
                onTap: () async {
                  await Supabase.instance.client.auth.signOut();
                  await GoogleSignIn().signOut();
                },
              ),

              const SizedBox(height: 6),

              // Notifications
              _SettingsRow(
                icon: Icons.notifications_outlined,
                gradient: _notificationsGradient,
                title: 'Notifications',
                trailing:
                    const Icon(Icons.chevron_right, color: Aurora.textMuted),
                onTap: () => context.push('/settings/notifications'),
              ),
              // Dictation
              _SettingsRow(
                icon: Icons.keyboard_voice_outlined,
                gradient: _dictationGradient,
                title: 'Dictation',
                subtitle: 'Transcription model & auto-submit',
                trailing:
                    const Icon(Icons.chevron_right, color: Aurora.textMuted),
                onTap: () => context.push('/settings/dictation'),
              ),
              // Wake word
              _SettingsRow(
                icon: Icons.mic_none_outlined,
                gradient: _wakeWordGradient,
                title: 'Wake word',
                subtitle: "'Hey Hearty' hands-free",
                trailing:
                    const Icon(Icons.chevron_right, color: Aurora.textMuted),
                onTap: () => context.push('/settings/wake-word'),
              ),
              // Conversation style
              _SettingsRow(
                icon: Icons.chat_bubble_outline,
                gradient: _conversationGradient,
                title: 'Conversation style',
                trailing:
                    const Icon(Icons.chevron_right, color: Aurora.textMuted),
                onTap: () => context.push('/settings/conversation'),
              ),

              const SizedBox(height: 6),

              // Health Profile
              _SettingsRow(
                icon: Icons.health_and_safety,
                gradient: _healthGradient,
                title: 'Health Profile',
                trailing:
                    const Icon(Icons.chevron_right, color: Aurora.textMuted),
                onTap: () => context.push('/health-profile'),
              ),

              const SizedBox(height: 6),

              // About
              _SettingsRow(
                icon: Icons.info_outline,
                gradient: _neutralGradient,
                title: 'About',
                subtitle: 'Hearty v1.0.0',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single glass-row settings entry: a 40px rounded gradient icon chip on the
/// left, title + optional subtitle in the middle, and an optional trailing
/// widget (e.g. a chevron) on the right. See design guide L2.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.gradient,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.titleColor,
  });

  final IconData icon;
  final Gradient gradient;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Aurora.glassFill,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Aurora.glassBorder),
            ),
            child: Row(
              children: [
                // 40px rounded gradient icon chip.
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Aurora.textPrimary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: titleColor ?? Aurora.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Aurora.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
