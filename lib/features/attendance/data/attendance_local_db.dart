import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/pending_attendance_record.dart';
import 'selfie_storage.dart';

/// SQLite-backed offline queue for attendance check-ins/outs.
///
/// Project sites often have poor or no connectivity, so every check-in/out
/// is written here first (status `pending`), then the sync service uploads
/// it in the background and flips the status to `synced` or `failed`.
/// Surviving app restarts is the whole point — this is the source of truth
/// for "did this device record an action today, and did it reach the server?"
class AttendanceLocalDb {
  static const _table = 'pending_attendance';

  Database? _db;

  /// [claimUserId] is only used the first time the database is opened after
  /// the per-user-scoping migration: pre-migration rows have no real owner,
  /// so they're attributed to whichever user happens to open the app first.
  /// That's correct for the common one-account-per-device case, and no
  /// leakier than the unscoped table they're migrating from.
  Future<Database> _open(int claimUserId) async {
    final existing = _db;
    if (existing != null) return existing;

    final dbPath = await getDatabasesPath();
    final db = await openDatabase(
      '$dbPath/attendance_queue.db',
      version: 3,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE $_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          type TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          selfie_path TEXT NOT NULL,
          recorded_at TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          error_message TEXT
        )
      '''),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN user_id INTEGER NOT NULL DEFAULT -1',
          );
        }
        if (oldVersion < 3) {
          // Catches both rows just defaulted to -1 above (devices upgrading
          // from v1) and rows stranded at -1 by an earlier build of this
          // migration that didn't claim them (devices already on v2).
          await db.update(
            _table,
            {'user_id': claimUserId},
            where: 'user_id = ?',
            whereArgs: [-1],
          );
        }
      },
    );
    _db = db;
    return db;
  }

  /// Inserts a freshly-captured record (owned by [userId]) and returns it
  /// with its local id.
  Future<PendingAttendanceRecord> insert(
    int userId,
    PendingAttendanceRecord record,
  ) async {
    final db = await _open(userId);
    final id = await db.insert(_table, {...record.toMap(), 'user_id': userId});
    return record.copyWith(id: id);
  }

  /// All queued records belonging to [userId], most recent first.
  Future<List<PendingAttendanceRecord>> getAll(int userId) async {
    final db = await _open(userId);
    final rows = await db.query(
      _table,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'recorded_at DESC',
    );
    return rows.map(PendingAttendanceRecord.fromMap).toList();
  }

  /// [userId]'s records that still need to reach the backend. Only
  /// `pending` ones: a `failed` record was rejected by the server's
  /// business rules (wrong day, outside window, duplicate, checkout
  /// without check-in) — deterministic rejections that would just fail
  /// again, so we never re-send them. They stay queued, surfaced to the
  /// user, until dismissed. Transient network/server errors leave the
  /// entry `pending`, so those still retry.
  Future<List<PendingAttendanceRecord>> getUnsynced(int userId) async {
    final db = await _open(userId);
    final rows = await db.query(
      _table,
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, AttendanceSyncStatus.pending.name],
      orderBy: 'recorded_at ASC',
    );
    return rows.map(PendingAttendanceRecord.fromMap).toList();
  }

  Future<void> updateStatus(
    int id,
    int userId, {
    required AttendanceSyncStatus status,
    String? errorMessage,
    bool clearError = false,
  }) async {
    final db = await _open(userId);
    await db.update(
      _table,
      {
        'status': status.name,
        'error_message': clearError ? null : errorMessage,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Basenames of every selfie still referenced by a queue row, across ALL
  /// users. Used by the startup sweep to delete orphaned selfie files without
  /// wiping another account's pending selfie on a shared device. [claimUserId]
  /// is only needed to open the DB (see [_open]); the query itself is unscoped.
  Future<Set<String>> referencedSelfieFileNames(int claimUserId) async {
    final db = await _open(claimUserId);
    final rows = await db.query(_table, columns: ['selfie_path']);
    return {
      for (final row in rows) selfieFileName(row['selfie_path'] as String),
    };
  }

  /// Permanently removes a queued record — used to dismiss a server-rejected
  /// (failed) entry the user has acknowledged.
  Future<void> delete(int id, int userId) async {
    final db = await _open(userId);
    await db.delete(
      _table,
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }
}

final attendanceLocalDbProvider = Provider<AttendanceLocalDb>((ref) {
  return AttendanceLocalDb();
});
