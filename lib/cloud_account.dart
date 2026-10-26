import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'totp.dart';
import 'cloud_vault.dart';

/// Account authentication only. TOTP secrets remain exclusively in local storage.
class CloudAccountPage extends StatefulWidget {
  final List<AuthAccount> localAccounts;
  final Future<int> Function(List<AuthAccount>) importAccounts;
  const CloudAccountPage({super.key, required this.localAccounts, required this.importAccounts});
  @override
  State<CloudAccountPage> createState() => _CloudAccountPageState();
}

class _CloudAccountPageState extends State<CloudAccountPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? notice;
  bool register = false;
  final master = TextEditingController();
  String? vaultNotice;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    master.dispose();
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

  Future<void> uploadVault() async {
    if (busy) return;
    if (master.text.length < 12) { setState(() => vaultNotice = 'Master password must be at least 12 characters.'); return; }
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Create encrypted cloud vault?'),
      content: Text('Encrypt and upload ${widget.localAccounts.length} local accounts. This is a one-time first upload. Keep your master password safe; it cannot be reset.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Encrypt & Upload'))],
    ));
    if (yes != true || !mounted) return;
    setState(() { busy = true; vaultNotice = null; });
    try {
      await CloudVaultService.firstUpload(List<AuthAccount>.of(widget.localAccounts), master.text);
      if (mounted) setState(() => vaultNotice = 'Encrypted vault uploaded. Existing local accounts unchanged.');
    } catch (e) { if (mounted) setState(() => vaultNotice = 'Upload failed: $e'); }
    finally { master.clear(); if (mounted) setState(() => busy = false); }
  }

  Future<void> restoreVault() async {
    if (busy) return;
    if (master.text.isEmpty) { setState(() => vaultNotice = 'Enter the vault master password.'); return; }
    setState(() { busy = true; vaultNotice = null; });
    try {
      final imported = await CloudVaultService.download(master.text);
      if (!mounted) return;
      final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Restore cloud vault?'),
        content: Text('Add up to ${imported.length} accounts to this device. Existing local accounts will not be deleted.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add accounts'))],
      ));
      if (yes == true) {
        final count = await widget.importAccounts(imported);
        if (mounted) setState(() => vaultNotice = 'Restored $count new accounts. Existing accounts preserved.');
      }
    } catch (e) { if (mounted) setState(() => vaultNotice = 'Restore failed: $e'); }
    finally { master.clear(); if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final configured = CloudAuthConfig.initialized;
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
        ListTile(leading: const Icon(Icons.verified_user_outlined), title: Text(session.user.email ?? 'Signed in'), subtitle: const Text('Signed in. Optional encrypted manual vault available below.')),
        const SizedBox(height: 12),
        const Text('Encrypted Cloud Vault', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('Use a separate master password (minimum 12 characters). This password cannot be recovered or reset.'),
        const SizedBox(height: 12),
        TextField(controller: master, obscureText: true, enableSuggestions: false, autocorrect: false, decoration: const InputDecoration(labelText: 'Vault master password', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton(onPressed: busy ? null : uploadVault, child: const Text('First encrypted upload')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: busy ? null : restoreVault, child: const Text('Restore encrypted vault to this device')),
        if (vaultNotice != null) Text(vaultNotice!),
        const SizedBox(height: 24),
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
      const Text('Manual encrypted cloud backup only. Automatic synchronization, vault updates and recovery keys are not available yet. Never lose your master password or independent recovery codes.'),
    ]);
  }
}

class CloudAuthConfig {
  static bool initialized = false;
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static bool get isConfigured => url.startsWith('https://') && publishableKey.isNotEmpty;
}
