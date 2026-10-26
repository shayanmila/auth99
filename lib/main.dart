import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'totp.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const EasyAuthenticator()); }

class EasyAuthenticator extends StatelessWidget {
  const EasyAuthenticator({super.key});
  @override Widget build(BuildContext context) => MaterialApp(title: 'Easy Authenticator', debugShowCheckedModeBanner: false, theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5066D9)), useMaterial3: true), darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B9AFF), brightness: Brightness.dark), useMaterial3: true), themeMode: ThemeMode.system, home: const HomePage());
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState() => _HomePageState(); }
class _HomePageState extends State<HomePage> {
  static const storage = FlutterSecureStorage();
  final List<AuthAccount> accounts = [];
  Timer? timer;
  DateTime now = DateTime.now();
  String query = '';
  bool loading = true;
  @override void initState() { super.initState(); _load(); timer = Timer.periodic(const Duration(seconds: 1), (_) { if(mounted) setState(() => now = DateTime.now()); }); }
  @override void dispose() { timer?.cancel(); super.dispose(); }
  Future<void> _load() async {
    try { final value = await storage.read(key: 'easy_auth_accounts_v1'); if(value != null) accounts.addAll(deserializeAccounts(value)); }
    catch (e) { if(mounted) _message('Unable to read encrypted storage: $e'); }
    if(mounted) setState(() => loading = false);
  }
  Future<void> _save() async { await storage.write(key: 'easy_auth_accounts_v1', value: serializeAccounts(accounts)); if(mounted) setState(() {}); }
  void _message(String text) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }
  Future<void> _add(AuthAccount account) async { try { decodeBase32(account.secret); accounts.add(account); await _save(); _message('Account added'); } catch(e) { _message('Unable to save account: $e'); } }
  Future<void> _delete(AuthAccount a) async {
    final confirmed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Delete account?'), content: Text('Remove ${a.issuer} ${a.name}? This cannot be undone without the original setup secret.'), actions: [TextButton(onPressed: () => Navigator.pop(c,false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c,true), child: const Text('Delete'))]));
    if(confirmed == true) { accounts.removeWhere((e) => e.id == a.id); try { await _save(); } catch(e) { _message('Unable to save deletion: $e'); } }
  }
  Future<void> _addManual() async {
    final issuer = TextEditingController(), name = TextEditingController(), secret = TextEditingController();
    final result = await showDialog<AuthAccount>(context: context, builder: (ctx) => AlertDialog(title: const Text('Add account manually'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: issuer, decoration: const InputDecoration(labelText: 'Service / issuer')), TextField(controller: name, decoration: const InputDecoration(labelText: 'Account name')), TextField(controller: secret, decoration: const InputDecoration(labelText: 'Base32 setup key'), autocorrect: false, enableSuggestions: false)])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () { try { decodeBase32(secret.text); Navigator.pop(ctx, AuthAccount(id: DateTime.now().microsecondsSinceEpoch.toString(), issuer: issuer.text.trim(), name: name.text.trim().isEmpty ? 'Account' : name.text.trim(), secret: secret.text.trim())); } catch (_) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Invalid Base32 key'))); } }, child: const Text('Save'))]));
    issuer.dispose(); name.dispose(); secret.dispose(); if(result != null) await _add(result);
  }
  Future<void> _scan() async {
    if(defaultTargetPlatform != TargetPlatform.android) { _message('QR camera scanning is currently Android-only. Use manual entry on Windows.'); return; }
    final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanPage()));
    if(result != null) { try { await _add(parseOtpAuth(result)); } catch(e) { _message('Invalid QR code: $e'); } }
  }
  @override Widget build(BuildContext context) {
    final filtered = accounts.where((a) => '${a.issuer} ${a.name}'.toLowerCase().contains(query.toLowerCase())).toList();
    return Scaffold(appBar: AppBar(title: const Text('Easy Authenticator'), actions: [IconButton(tooltip: 'Add manually', onPressed: _addManual, icon: const Icon(Icons.add))]), body: loading ? const Center(child: CircularProgressIndicator()) : Column(children: [Padding(padding: const EdgeInsets.all(16), child: TextField(onChanged: (s) => setState(() => query = s), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search accounts', border: OutlineInputBorder()))), Expanded(child: filtered.isEmpty ? Center(child: Text(accounts.isEmpty ? 'No accounts yet. Add your first 2FA account.' : 'No matching accounts.')) : ListView.builder(itemCount: filtered.length, itemBuilder: (context,i) { final a = filtered[i]; final remaining = a.period - (now.millisecondsSinceEpoch ~/ 1000) % a.period; final code = totp(a, now: now); return Card(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [CircleAvatar(child: Text((a.issuer.isNotEmpty ? a.issuer : a.name).substring(0,1).toUpperCase())), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.issuer.isEmpty ? 'Account' : a.issuer, style: Theme.of(context).textTheme.titleMedium), Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis)])), PopupMenuButton<String>(onSelected: (v) { if(v == 'delete') _delete(a); }, itemBuilder: (_) => [const PopupMenuItem(value: 'delete', child: Text('Delete'))])]), const SizedBox(height: 12), Row(children: [Expanded(child: SelectableText(code.length == 6 ? '${code.substring(0,3)} ${code.substring(3)}' : '${code.substring(0,4)} ${code.substring(4)}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))), IconButton(tooltip: 'Copy code', onPressed: () async { await Clipboard.setData(ClipboardData(text: code)); _message('Code copied'); }, icon: const Icon(Icons.copy)), Text('${remaining}s')]), LinearProgressIndicator(value: remaining / a.period)]))); } ))]), floatingActionButton: FloatingActionButton.extended(onPressed: () => showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.qr_code_scanner), title: const Text('Scan QR code (Android)'), onTap: () { Navigator.pop(ctx); _scan(); }), ListTile(leading: const Icon(Icons.key), title: const Text('Enter setup key'), onTap: () { Navigator.pop(ctx); _addManual(); })]))), icon: const Icon(Icons.add), label: const Text('Add account')));
  }
}

class ScanPage extends StatefulWidget { const ScanPage({super.key}); @override State<ScanPage> createState() => _ScanPageState(); }
class _ScanPageState extends State<ScanPage> {
  bool scanned = false;
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Scan 2FA QR code')), body: MobileScanner(onDetect: (capture) { if(scanned) return; for(final barcode in capture.barcodes) { final raw = barcode.rawValue; if(raw != null && raw.startsWith('otpauth://')) { scanned = true; Navigator.pop(context, raw); return; } } }));
}
