import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Account authentication only. TOTP secrets remain exclusively in local storage.
class CloudAccountPage extends StatefulWidget {
  const CloudAccountPage({super.key});
  @override
  State<CloudAccountPage> createState() => _CloudAccountPageState();
}

class _CloudAccountPageState extends State<CloudAccountPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? notice;
  bool register = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (!email.text.contains('@') || password.text.length < 8) {
      setState(() => notice = 'Enter a valid email and a password of at least 8 characters.');
      return;
    }
    setState(() { busy = true; notice = null; });
    try {
      final client = Supabase.instance.client;
      if (register) {
        final result = await client.auth.signUp(email: email.text.trim(), password: password.text);
        if (!mounted) return;
        setState(() => notice = result.session == null
            ? 'Registration submitted. Check your email to confirm your account.'
            : 'Account created. Signed in successfully.');
      } else {
        await client.auth.signInWithPassword(email: email.text.trim(), password: password.text);
        if (!mounted) return;
        setState(() => notice = 'Signed in successfully.');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => notice = e.message);
    } catch (_) {
      if (mounted) setState(() => notice = 'Unable to connect. Check your internet connection.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = CloudAuthConfig.isConfigured;
    final session = configured ? Supabase.instance.client.auth.currentSession : null;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Cloud Account', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      const Text('Optional sign-in. All existing authenticator accounts stay offline and remain available without a cloud account.'),
      const SizedBox(height: 16),
      if (!configured) const Card(child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('Cloud account service is not configured yet. Add Supabase project URL and publishable/anon key at build time. Offline authentication remains fully functional.'),
      ))
      else if (session != null) ...[
        ListTile(leading: const Icon(Icons.verified_user_outlined), title: Text(session.user.email ?? 'Signed in'), subtitle: const Text('Cloud account connected. TOTP sync is not enabled yet.')),
        FilledButton.tonal(onPressed: busy ? null : () async {
          setState(() => busy = true);
          try { await Supabase.instance.client.auth.signOut(); }
          catch (_) { if (mounted) setState(() => notice = 'Could not sign out.'); }
          finally { if (mounted) setState(() => busy = false); }
        }, child: const Text('Sign out')),
      ] else ...[
        SegmentedButton<bool>(segments: const [
          ButtonSegment(value: false, label: Text('Sign in')),
          ButtonSegment(value: true, label: Text('Register')),
        ], selected: {register}, onSelectionChanged: busy ? null : (v) => setState(() { register = v.first; notice = null; })),
        const SizedBox(height: 16),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: password, obscureText: true, enableSuggestions: false, autocorrect: false, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait...' : register ? 'Create account' : 'Sign in')),
      ],
      if (notice != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(notice!)),
      const SizedBox(height: 24),
      const Text('Phase 1: account registration and login only. No TOTP secret, account label, backup or recovery data is uploaded. Encrypted synchronization will require a separate vault setup.'),
    ]);
  }
}

class CloudAuthConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static bool get isConfigured => url.startsWith('https://') && publishableKey.isNotEmpty;
}
