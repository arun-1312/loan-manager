import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'loan_math.dart';

// ==============================================================================
// 1. CONFIGURATION
// ==============================================================================

class DbConfig {
  static const String dbName = 'loan_manager_secure.db';
  static const int dbVersion = 5;

  static const String keyDbEncryption = 'db_encryption_key';
  static const String keyAppPin = 'app_pin_hash';
  static const String keyFirstTimeUser = 'first_time_user';
  static const String keyLastBackup = 'last_backup_timestamp';

  static const String tableLoans = 'loans';
  static const String tableTransactions = 'loan_transactions';
  static const String tableSettings = 'app_settings';
}

// ==============================================================================
// 2. SECURITY (Production Grade DB Key + App PIN)
// ==============================================================================

class _DbSecurity {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<String> getOrCreateDbKey() async {
    String? key = await _storage.read(key: DbConfig.keyDbEncryption);
    if (key == null) {
      key = _generateSecureKey();
      await _storage.write(key: DbConfig.keyDbEncryption, value: key);
      debugPrint('🔐 DB: Generated new secure encryption key');
      return key;
    }
    return key;
  }

  /// Generates a cryptographically secure random key (32 bytes, base64url encoded)
  static String _generateSecureKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(values);
  }
}

class SecurityService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<bool> setAppPin(String pin) async {
    try {
      final pinHash = _hashPin(pin);
      await _storage.write(key: DbConfig.keyAppPin, value: pinHash);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> verifyAppPin(String pin) async {
    try {
      final storedHash = await _storage.read(key: DbConfig.keyAppPin);
      final inputHash = _hashPin(pin);
      return storedHash == inputHash;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isPinSet() async {
    final pinHash = await _storage.read(key: DbConfig.keyAppPin);
    return pinHash != null && pinHash.isNotEmpty;
  }

  static Future<bool> isFirstTimeUser() async {
    final firstTime = await _storage.read(key: DbConfig.keyFirstTimeUser);
    return firstTime == null;
  }

  static Future<void> markFirstTimeCompleted() async {
    await _storage.write(
      key: DbConfig.keyFirstTimeUser,
      value: 'completed',
    );
  }

  static String _hashPin(String pin) {
    // Simple salted encoding. For serious security, swap to PBKDF2/argon2.
    const salt = 'sunmaart_salt_v1';
    return base64Url.encode(utf8.encode('$salt$pin'));
  }
}

// ==============================================================================
// 3. NOTIFICATION MANAGER (Uses DB Public API)
// ==============================================================================

class NotificationManager {
  static Future<List<Map<String, dynamic>>> getDueLoansForNotification() async {
    final dbHelper = DatabaseHelper.instance;
    final allLoans = await dbHelper.getAllLoans();
    final dueLoans = <Map<String, dynamic>>[];

    for (final loan in allLoans) {
      if ((loan['status'] ?? 'active') == 'active') {
        final dueStatus = await dbHelper.getLoanDueStatus(loan['id']);
        final unpaidMonths = dueStatus?['unpaid_months'] ?? 0;
        if (unpaidMonths > 0) {
          dueLoans.add({
            'loan': loan,
            'due_status': dueStatus,
            'unpaid_months': unpaidMonths,
          });
        }
      }
    }
    return dueLoans;
  }

  static Future<List<Map<String, dynamic>>> getUpcomingDueLoans() async {
    final dbHelper = DatabaseHelper.instance;
    final allLoans = await dbHelper.getAllLoans();
    final upcomingLoans = <Map<String, dynamic>>[];

    final now = DateTime.now();
    final nextWeek = now.add(const Duration(days: 7));

    for (final loan in allLoans) {
      if ((loan['status'] ?? 'active') == 'active') {
        final unpaidEntries = await dbHelper.getLoanUnpaidEntries(loan['id']);
        final nextDue = unpaidEntries?['next_due'];

        if (nextDue != null && nextDue['due_date'] is DateTime) {
          final dueDate = nextDue['due_date'] as DateTime;
          if (dueDate.isAfter(now) && dueDate.isBefore(nextWeek)) {
            upcomingLoans.add({
              'loan': loan,
              'next_due': nextDue,
            });
          }
        }
      }
    }
    return upcomingLoans;
  }
}

// ==============================================================================
// 4. MAIN DATABASE HELPER
// ==============================================================================

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  DatabaseHelper._privateConstructor();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // ---------------------------------------------------------------------------
  // DB INIT / SCHEMA
  // ---------------------------------------------------------------------------

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, DbConfig.dbName);
    final String dbPassword = await _DbSecurity.getOrCreateDbKey();

    return await openDatabase(
      path,
      password: dbPassword,
      version: DbConfig.dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${DbConfig.tableLoans} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_given_date TEXT,
        borrower_name TEXT NOT NULL,
        borrower_place TEXT,
        borrower_phone TEXT,
        related_person_title TEXT,
        related_person_name TEXT,
        related_person_phone TEXT,
        principal_amount REAL NOT NULL,
        original_principal REAL NOT NULL,
        interest_rate_percent REAL NOT NULL,
        start_date TEXT,
        fixed_due_day INTEGER,
        status TEXT DEFAULT 'active',
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbConfig.tableTransactions} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id INTEGER,
        payment_date TEXT,
        months_paid INTEGER,
        interest_paid REAL,
        principal_paid REAL,
        new_principal_balance REAL,
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (loan_id) REFERENCES ${DbConfig.tableLoans} (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbConfig.tableSettings} (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (int version = oldVersion + 1; version <= newVersion; version++) {
      if (version == 2) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ${DbConfig.tableTransactions} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            loan_id INTEGER,
            payment_date TEXT,
            months_paid INTEGER,
            interest_paid REAL,
            principal_paid REAL,
            new_principal_balance REAL,
            notes TEXT,
            created_at TEXT,
            FOREIGN KEY (loan_id) REFERENCES ${DbConfig.tableLoans} (id)
          )
        ''');
      } else if (version == 3) {
        await _safeAlterTable(db, DbConfig.tableLoans, 'loan_given_date TEXT');
      } else if (version == 4) {
        await _safeAlterTable(
          db,
          DbConfig.tableLoans,
          'created_at TEXT DEFAULT CURRENT_TIMESTAMP',
        );
        await _safeAlterTable(
          db,
          DbConfig.tableLoans,
          'updated_at TEXT DEFAULT CURRENT_TIMESTAMP',
        );
      } else if (version == 5) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ${DbConfig.tableSettings} (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      }
    }
  }

  Future<void> _safeAlterTable(Database db, String table, String columnDef) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $columnDef');
    } catch (e) {
      debugPrint('⚠️ Migration Info: Column likely exists in $table. $e');
    }
  }

  // ---------------------------------------------------------------------------
  // LOANS - CRUD
  // ---------------------------------------------------------------------------

  Future<int> insertLoan(Map<String, dynamic> loanData) async {
    final db = await database;
    try {
      final data = Map<String, dynamic>.from(loanData);
      final nowIso = DateTime.now().toIso8601String();
      data['created_at'] ??= nowIso;
      data['updated_at'] = nowIso;
      return await db.insert(DbConfig.tableLoans, data);
    } catch (e) {
      debugPrint('❌ insertLoan error: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getAllLoans() async {
    final db = await database;
    return await db.query(DbConfig.tableLoans, orderBy: 'id DESC');
  }

  Future<Map<String, dynamic>?> getLoanById(int loanId) async {
    final db = await database;
    final results = await db.query(
      DbConfig.tableLoans,
      where: 'id = ?',
      whereArgs: [loanId],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> closeLoan(int loanId) async {
    final db = await database;
    return await db.update(
      DbConfig.tableLoans,
      {
        'status': 'closed',
        'principal_amount': 0.0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [loanId],
    );
  }

  // ---------------------------------------------------------------------------
  // TRANSACTIONS - CRUD
  // ---------------------------------------------------------------------------

  Future<int> insertTransaction(
    Map<String, dynamic> transactionData, {
    bool adjustPrincipal = true,
  }) async {
    final db = await database;

    return await db.transaction<int>((txn) async {
      final data = Map<String, dynamic>.from(transactionData);
      final nowIso = DateTime.now().toIso8601String();
      data['created_at'] ??= nowIso;

      final double principalPaid =
          LoanMath.parseDouble(data['principal_paid'], defaultValue: 0.0);
      data['months_paid'] =
          LoanMath.parseInt(data['months_paid'], defaultValue: 0);

      if (adjustPrincipal && principalPaid > 0) {
        final List<Map<String, Object?>> rows = await txn.query(
          DbConfig.tableLoans,
          columns: ['principal_amount'],
          where: 'id = ?',
          whereArgs: [data['loan_id']],
        );

        if (rows.isNotEmpty) {
          final currentPrincipal =
              (rows.first['principal_amount'] as num?)?.toDouble() ?? 0.0;
          final newPrincipal = currentPrincipal - principalPaid;
          final clampedPrincipal = newPrincipal < 0 ? 0.0 : newPrincipal;

          await txn.update(
            DbConfig.tableLoans,
            {
              'principal_amount': clampedPrincipal,
              'updated_at': nowIso,
            },
            where: 'id = ?',
            whereArgs: [data['loan_id']],
          );
          data['new_principal_balance'] = clampedPrincipal;
        }
      }

      return await txn.insert(DbConfig.tableTransactions, data);
    });
  }

  Future<List<Map<String, dynamic>>> getLoanTransactions(int loanId) async {
    final db = await database;
    return await db.query(
      DbConfig.tableTransactions,
      where: 'loan_id = ?',
      whereArgs: [loanId],
      orderBy: 'payment_date DESC',
    );
  }

  // ---------------------------------------------------------------------------
  // STATS
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getDatabaseStats() async {
    final db = await database;

    final loansCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${DbConfig.tableLoans}'),
        ) ??
        0;

    final txCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${DbConfig.tableTransactions}'),
        ) ??
        0;

    final resultPrincipal = await db.rawQuery(
      "SELECT SUM(principal_amount) as total "
      "FROM ${DbConfig.tableLoans} WHERE status = 'active'",
    );
    final totalPrincipal =
        (resultPrincipal.first['total'] as num?)?.toDouble() ?? 0.0;

    final activeCount = Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM ${DbConfig.tableLoans} WHERE status = 'active'",
          ),
        ) ??
        0;

    return {
      'total_loans': loansCount,
      'active_loans': activeCount,
      'closed_loans': loansCount - activeCount,
      'total_transactions': txCount,
      'total_principal': totalPrincipal,
      'last_updated': DateTime.now().toIso8601String(),
    };
  }

  // ---------------------------------------------------------------------------
  // DOMAIN QUERIES (Loan due logic)
// ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> getLoanDueStatus(int loanId) async {
    final loan = await getLoanById(loanId);
    if (loan == null) return null;

    final transactions = await getLoanTransactions(loanId);
    final dateStr =
        (loan['loan_given_date'] ?? loan['start_date'])?.toString();

    if (dateStr == null || dateStr.isEmpty) {
      return {
        'loanId': loanId,
        'borrower_name': loan['borrower_name'],
        'unpaid_months': 0,
        'last_paid': null,
        'total_due_count': 0,
        'months_paid': 0,
      };
    }

    final loanStartDate = DateTime.tryParse(dateStr) ?? DateTime.now();
    final fixedDueDay = LoanMath.getFixedDueDay(loan, loanStartDate);
    final now = DateTime.now();

    final dueCount =
        LoanMath.calculateDueCount(loanStartDate, fixedDueDay, now);
    final monthsPaid = LoanMath.calculateMonthsPaid(transactions);
    final unpaidMonths = (dueCount - monthsPaid) > 0
        ? (dueCount - monthsPaid)
        : 0;
    final lastPaid = LoanMath.getLastPaidDate(transactions);

    return {
      'loanId': loanId,
      'borrower_name': loan['borrower_name'],
      'unpaid_months': unpaidMonths,
      'last_paid': lastPaid,
      'total_due_count': dueCount,
      'months_paid': monthsPaid,
    };
  }

  Future<Map<String, dynamic>?> getLoanUnpaidEntries(int loanId) async {
    final loan = await getLoanById(loanId);
    if (loan == null) return null;

    final transactions = await getLoanTransactions(loanId);
    final dateStr =
        (loan['loan_given_date'] ?? loan['start_date'])?.toString();
    if (dateStr == null || dateStr.isEmpty) return null;

    final loanStartDate = DateTime.tryParse(dateStr) ?? DateTime.now();
    final fixedDueDay = LoanMath.getFixedDueDay(loan, loanStartDate);
    final now = DateTime.now();

    final dueCount =
        LoanMath.calculateDueCount(loanStartDate, fixedDueDay, now);
    final dueDates =
        LoanMath.generateDueDates(loanStartDate, fixedDueDay, dueCount);
    final monthsPaid =
        LoanMath.calculateMonthsPaid(transactions);
    final paidStatus =
        LoanMath.calculatePaidStatus(dueDates.length, monthsPaid);

    final unpaidEntries = LoanMath.buildUnpaidEntriesList(
      dueDates: dueDates,
      paidStatus: paidStatus,
      now: now,
      loan: loan,
      transactions: transactions,
    );

    final nextDue =
        LoanMath.buildNextDueObject(loanStartDate, fixedDueDay, dueCount);

    return {
      'loanId': loanId,
      'borrower_name': loan['borrower_name'],
      'unpaid_count': unpaidEntries.length,
      'unpaid_entries': unpaidEntries,
      'next_due': nextDue,
    };
  }

  Future<List<Map<String, dynamic>>> getDetailedReportData() async {
    final db = await DatabaseHelper.instance.database;
    final loans = await db.query(DbConfig.tableLoans, orderBy: 'id DESC');

    final List<Map<String, dynamic>> reportData = [];

    for (var loan in loans) {
      final int loanId = (loan['id'] as num).toInt();
      final double principal = (loan['principal_amount'] as num?)?.toDouble() ?? 0.0;
      final int dueDay = (loan['fixed_due_day'] as num?)?.toInt() ?? 1;
      final String startDateStr = (loan['loan_given_date'] ?? loan['created_at'] ?? '') as String;
      final DateTime startDate = DateTime.tryParse(startDateStr) ?? DateTime.now();

      final txns = await db.query(
        DbConfig.tableTransactions,
        where: 'loan_id = ?',
        whereArgs: [loanId],
      );

      double totalInterestRec = 0.0;
      int duesPaidCount = 0;

      for (var t in txns) {
        totalInterestRec += (t['interest_paid'] as num?)?.toDouble() ?? 0.0;
        duesPaidCount += (t['months_paid'] as num?)?.toInt() ?? 0;
      }

      final DateTime now = DateTime.now();
      int duesPassed = (now.year - startDate.year) * 12 + now.month - startDate.month;
      if (now.day < dueDay) duesPassed--;
      if (duesPassed < 0) duesPassed = 0;
      final int duesPending = duesPassed - duesPaidCount;

      reportData.add({
        'id': loanId,
        'name': loan['borrower_name'],
        'place': loan['borrower_place'],
        'start_date': startDateStr,
        'principal': principal,
        'rate': loan['interest_rate_percent'],
        'dues_passed': duesPassed,
        'dues_paid': duesPaidCount,
        'dues_pending': duesPending,
        'total_interest': totalInterestRec,
        'status': loan['status'],
      });
    }

    return reportData;
  }
}

