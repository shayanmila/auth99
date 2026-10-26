import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'backup.dart';
import 'totp.dart';

/// Phase 2 manual encrypted vault. Never transmits plaintext TOTP material.
class CloudVaultService {
  static Future<void> firstUpload(List<AuthAccount> accounts, String masterPassword) async {
    if (accounts.isEmpty) throw StateError('There are no local accounts to upload.');
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before uploading.');
    final existing = await client.from('encrypted_vaults').select('revision').eq('user_id', user.id).maybeSingle();
    if (existing != null) throw StateError('Cloud vault already exists. Upload blocked to prevent overwriting another device.');
    final bytes = await BackupCodec.export(accounts, masterPassword);
    final envelope = jsonDecode(utf8.decode(bytes));
    await client.from('encrypted_vaults').insert({
      'user_id': user.id,
      'envelope': envelope,
      'revision': 1,
    });
  }

  static Future<List<AuthAccount>> download(String masterPassword) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before restoring.');
    final row = await client.from('encrypted_vaults').select('envelope').eq('user_id', user.id).maybeSingle();
    if (row == null) throw StateError('No encrypted cloud vault found for this account.');
    final raw = utf8.encode(jsonEncode(row['envelope']));
    return BackupCodec.restore(Uint8List.fromList(raw), masterPassword);
  }
}
