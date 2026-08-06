import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocaleProvider extends ChangeNotifier {
  final FlutterSecureStorage _storage;
  Locale? _locale;
  bool _isInitialized = false;

  LocaleProvider({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage() {
    _loadPersistedLocale();
  }

  Locale? get locale => _locale;
  bool get isInitialized => _isInitialized;

  Future<void> _loadPersistedLocale() async {
    try {
      final savedCode = await _storage.read(key: 'language_code');
      if (savedCode == 'en') {
        _locale = const Locale('en');
      } else if (savedCode == 'ar') {
        _locale = const Locale('ar');
      } else {
        _locale = null; // Auto-detect
      }
    } catch (e) {
      debugPrint('Error loading language code: $e');
      _locale = null;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale? newLocale) async {
    _locale = newLocale;
    notifyListeners();

    try {
      if (newLocale == null) {
        await _storage.write(key: 'language_code', value: 'auto');
      } else {
        await _storage.write(
            key: 'language_code', value: newLocale.languageCode);
      }
    } catch (e) {
      debugPrint('Error saving language code: $e');
    }
  }
}
