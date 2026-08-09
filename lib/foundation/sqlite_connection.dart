import 'package:sqlite3/sqlite3.dart';

Database openSqliteDatabase(String path) {
  final db = sqlite3.open(path);
  // busy_timeout must be applied before the journal mode switch: switching to
  // DELETE requires an exclusive lock, and without the timeout a concurrent
  // connection can fail immediately with "database is locked".
  db.execute('PRAGMA busy_timeout = 5000;');
  db.execute('PRAGMA journal_mode = DELETE;');
  db.execute('PRAGMA synchronous = NORMAL;');
  return db;
}

/// Execute a function with a temporary database connection, ensuring cleanup.
/// Use this in Isolate operations to avoid manual open/dispose boilerplate.
Future<T> withDatabase<T>(
  String path,
  Future<T> Function(Database db) fn,
) async {
  final db = openSqliteDatabase(path);
  try {
    return await fn(db);
  } finally {
    db.dispose();
  }
}
