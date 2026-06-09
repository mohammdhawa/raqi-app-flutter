import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/pending_attendance_record.dart';

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

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;

    final dbPath = await getDatabasesPath();
    final db = await openDatabase(
      '$dbPath/attendance_queue.db',
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE $_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          selfie_path TEXT NOT NULL,
          recorded_at TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          error_message TEXT
        )
      '''),
    );
    _db = db;
    return db;
  }

  /// Inserts a freshly-captured record and returns it with its local id.
  Future<PendingAttendanceRecord> insert(PendingAttendanceRecord record) async {
    final db = await _open();
    final id = await db.insert(_table, record.toMap());
    return record.copyWith(id: id);
  }

  /// All queued records, most recent first.
  Future<List<PendingAttendanceRecord>> getAll() async {
    final db = await _open();
    final rows = await db.query(_table, orderBy: 'recorded_at DESC');
    return rows.map(PendingAttendanceRecord.fromMap).toList();
  }

  /// Records that still need to reach the backend — `pending` plus
  /// `failed` ones (so connectivity restoration retries them too).
  Future<List<PendingAttendanceRecord>> getUnsynced() async {
    final db = await _open();
    final rows = await db.query(
      _table,
      where: 'status IN (?, ?)',
      whereArgs: [
        AttendanceSyncStatus.pending.name,
        AttendanceSyncStatus.failed.name,
      ],
      orderBy: 'recorded_at ASC',
    );
    return rows.map(PendingAttendanceRecord.fromMap).toList();
  }

  Future<void> updateStatus(
    int id, {
    required AttendanceSyncStatus status,
    String? errorMessage,
    bool clearError = false,
  }) async {
    final db = await _open();
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
}

final attendanceLocalDbProvider = Provider<AttendanceLocalDb>((ref) {
  return AttendanceLocalDb();
});
