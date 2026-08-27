import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/error_log.dart';
import '../domain/leave.dart';

/// Local copy of the leave-type vocabulary (`GET /attendance/leave-types`).
///
/// The list changes rarely but is NOT static — an admin can add a type at any
/// time — so it is cached rather than hardcoded, and refreshed on every read
/// that reaches the network. The cache only covers the offline case: it keeps
/// the picker usable on a site with no signal, where the alternative is
/// refusing to file the request at all.
///
/// Entries are keyed by **user and form**:
///
///  * per form ([LeaveTypeForm]) because the two lists genuinely differ — a
///    type HR may pick to excuse an absence is not necessarily one an employee
///    may request, and reading the wrong one back would put a 422 in the
///    picker;
///  * per user because this is a shared device. The vocabulary is scoped to
///    whoever asked for it, so serving one account's list to the next person
///    who signs in would show them types that are not theirs — from cache,
///    with no request the server could refuse. [clear] wipes the lot on
///    logout; the per-user key is what protects the window before it runs.
class LeaveTypeCache {
  const LeaveTypeCache();

  static const _keyPrefix = 'leave_types_';

  String _keyFor(int userId, LeaveTypeForm form) =>
      '$_keyPrefix${userId}_${form.apiValue}';

  /// Overwrites [userId]'s cached list for [form]. Best-effort: a storage
  /// failure costs an offline picker, never the request the user just made.
  Future<void> save(
    int userId,
    LeaveTypeForm form,
    List<LeaveType> types,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _keyFor(userId, form),
        jsonEncode([for (final t in types) t.toJson()]),
      );
    } catch (e, stack) {
      // Through the safe helper: a SharedPreferences/PlatformException carries
      // an on-device path or the platform channel's payload, and debugPrint is
      // NOT compiled out of release builds. Release keeps the type only.
      logUnexpected('Could not cache leave types', e, stack);
    }
  }

  /// [userId]'s cached list for [form], or empty when nothing is cached, the
  /// payload no longer parses (an older shape), or storage is unreadable.
  Future<List<LeaveType>> read(int userId, LeaveTypeForm form) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyFor(userId, form));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map) LeaveType.fromJson(entry.cast<String, dynamic>()),
      ].where((t) => t.id != 0).toList();
    } catch (e, stack) {
      logUnexpected('Could not read cached leave types', e, stack);
      return const [];
    }
  }

  /// Drops every cached vocabulary, for every user and form.
  ///
  /// Called when a session ends. Scoping by user already stops one account
  /// reading another's list; this stops the list outliving the session that
  /// fetched it at all, including the unkeyed entries written by builds
  /// before the key carried a user id.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(_keyPrefix)) await prefs.remove(key);
      }
    } catch (e, stack) {
      logUnexpected('Could not clear cached leave types', e, stack);
    }
  }
}

final leaveTypeCacheProvider = Provider<LeaveTypeCache>((ref) {
  return const LeaveTypeCache();
});
