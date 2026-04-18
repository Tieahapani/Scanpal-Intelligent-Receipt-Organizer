import 'package:flutter/material.dart';
import 'api.dart';
import 'auth_service.dart';
import 'login_page.dart';
import 'profile_page.dart';
import 'change_password_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _darkMode = false;
  bool _notifications = true;
  bool _isDeletingAccount = false;

  Future<void> _logout() async {
    await AuthService.instance.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _confirmDeleteAccount() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),

                // Warning icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 28,
                    color: Colors.red.shade600,
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                const Text(
                  'Delete Account?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),

                // Description
                Text(
                  'This will permanently delete your account, all receipts, and trip data. This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                // Delete button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Delete My Account',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Cancel button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((confirmed) async {
      if (confirmed != true || !mounted) return;

      setState(() => _isDeletingAccount = true);

      try {
        await APIService().deleteAccount();
        await AuthService.instance.clearAll();
        if (!mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF46166B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Flexible(
                  child: Text('Account deleted successfully',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _isDeletingAccount = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade600,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.toString().replaceAll('Exception: ', ''),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: CustomScrollView(
        slivers: [
          // Purple header
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF46166B), Color(0xFF5C2D91)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Expanded(
                            child: Text(
                              'Settings',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 40),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Gear icon
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      child: const Icon(
                        Icons.settings_outlined,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),

          // Settings sections
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ACCOUNT
                _sectionLabel('ACCOUNT'),
                const SizedBox(height: 10),
                _card([
                  _settingsRow(
                    icon: Icons.lock_outline,
                    label: 'Change Password',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
                      );
                    },
                  ),
                  _divider(),
                  _settingsRow(
                    icon: Icons.person_outline,
                    label: 'Edit Profile',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfilePage()),
                      );
                    },
                  ),
                ]),

                const SizedBox(height: 24),

                // PREFERENCES
                _sectionLabel('PREFERENCES'),
                const SizedBox(height: 10),
                _card([
                  _settingsToggleRow(
                    icon: Icons.dark_mode_outlined,
                    label: 'Dark Mode',
                    value: _darkMode,
                    onChanged: (val) => setState(() => _darkMode = val),
                  ),
                  _divider(),
                  _settingsToggleRow(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    value: _notifications,
                    onChanged: (val) => setState(() => _notifications = val),
                  ),
                ]),

                const SizedBox(height: 24),

                // ABOUT
                _sectionLabel('ABOUT'),
                const SizedBox(height: 10),
                _card([
                  _settingsRow(
                    icon: Icons.description_outlined,
                    label: 'Terms of Service',
                    onTap: () {},
                  ),
                  _divider(),
                  _settingsRow(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap: () {},
                  ),
                  _divider(),
                  _settingsInfoRow(
                    icon: Icons.info_outline,
                    label: 'App Version',
                    value: 'v2.0.0',
                  ),
                ]),

                const SizedBox(height: 24),

                // ACCOUNT ACTIONS
                _sectionLabel('ACCOUNT ACTIONS'),
                const SizedBox(height: 10),
                _card([
                  _settingsRow(
                    icon: Icons.logout,
                    label: 'Log Out',
                    isDestructive: true,
                    onTap: _logout,
                  ),
                  _divider(),
                  _settingsRow(
                    icon: Icons.delete_outline,
                    label: 'Delete Account',
                    isDestructive: true,
                    showLoading: _isDeletingAccount,
                    onTap: _isDeletingAccount ? null : _confirmDeleteAccount,
                  ),
                ]),

                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade500,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _settingsRow({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool isDestructive = false,
    bool showLoading = false,
  }) {
    final color = isDestructive ? Colors.red.shade600 : const Color(0xFF46166B);
    final bgColor = isDestructive
        ? Colors.red.shade50
        : const Color(0xFF46166B).withValues(alpha: 0.08);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDestructive ? Colors.red.shade600 : const Color(0xFF111827),
                ),
              ),
            ),
            if (showLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.red.shade600,
                ),
              )
            else if (!isDestructive)
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _settingsToggleRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF46166B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF46166B), size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF111827),
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF46166B),
            activeThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _settingsInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF46166B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF46166B), size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF111827),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.only(left: 66),
      child: Divider(height: 1, color: Colors.grey.shade100),
    );
  }
}
