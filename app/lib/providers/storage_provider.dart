import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sepot/core/storage/secure_storage.dart';

/// Globální instance úložiště
final storageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
