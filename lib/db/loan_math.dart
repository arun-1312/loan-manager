// lib/db/loan_math.dart

import 'package:flutter/foundation.dart';

/// Pure loan/domain math.
/// No SQL, no Flutter widgets, no storage.
/// Just calculations based on loan + transactions data.
class LoanMath {
  // ===========================================================================
  // SAFE PARSERS
  // ===========================================================================

  static int parseInt(dynamic value, {int defaultValue = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  static double parseDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  // ===========================================================================
  // DATE HELPERS
  // ===========================================================================

  /// Adds [months] months to [from] and clamps the day to the last day
  /// of the resulting month if needed.
  static DateTime addMonths(DateTime from, int months) {
    final int year = from.year + ((from.month - 1 + months) ~/ 12);
    final int month = ((from.month - 1 + months) % 12) + 1;
    final int lastDay = DateTime(year, month + 1, 0).day;
    final int day = from.day <= lastDay ? from.day : lastDay;
    return DateTime(year, month, day);
  }

  /// Builds a normalized "base" date that respects a fixed due day.
  static DateTime normalizedStartDate(
    DateTime original,
    int fixedDueDay,
  ) {
    final int lastDay =
        DateTime(original.year, original.month + 1, 0).day;
    final int day = fixedDueDay <= 0
        ? original.day
        : (fixedDueDay <= lastDay ? fixedDueDay : lastDay);

    return DateTime(original.year, original.month, day);
  }

  static String monthLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  // ===========================================================================
  // CORE CALCULATIONS
  // ===========================================================================

  static int getFixedDueDay(
    Map<String, dynamic> loan,
    DateTime loanStartDate,
  ) {
    final fixedDay = parseInt(loan['fixed_due_day'], defaultValue: 0);
    return fixedDay > 0 ? fixedDay : loanStartDate.day;
  }

  /// Returns how many due months exist from [startDate] until [now].
  static int calculateDueCount(
    DateTime startDate,
    int fixedDueDay,
    DateTime now,
  ) {
    int monthsBetween =
        (now.year - startDate.year) * 12 + (now.month - startDate.month);
    if (now.day < fixedDueDay) monthsBetween--;
    return monthsBetween >= 0 ? monthsBetween : 0;
  }

  /// Builds the full list of due dates from [loanStartDate] (or loan-given date)
  /// using a [fixedDueDay].
  static List<DateTime> generateDueDates(
    DateTime loanStartDate,
    int fixedDueDay,
    int dueCount,
  ) {
    final List<DateTime> dueDates = [];
    final base = normalizedStartDate(loanStartDate, fixedDueDay);
    for (int i = 1; i <= dueCount; i++) {
      dueDates.add(addMonths(base, i));
    }
    return dueDates;
  }

  static int calculateMonthsPaid(List<Map<String, dynamic>> transactions) {
    return transactions.fold<int>(0, (sum, t) {
      return sum + parseInt(t['months_paid'], defaultValue: 0);
    });
  }

  static List<bool> calculatePaidStatus(
    int totalDues,
    int totalMonthsPaid,
  ) {
    final List<bool> isPaid = List<bool>.filled(totalDues, false);
    for (int i = 0; i < totalMonthsPaid && i < totalDues; i++) {
      isPaid[i] = true; // oldest-first
    }
    return isPaid;
  }

  /// Transactions expected in DESC order (latest first) from DB.
  /// Returns the *latest* paid date.
  static DateTime? getLastPaidDate(List<Map<String, dynamic>> transactions) {
    if (transactions.isEmpty) return null;

    // DB returns DESC (latest first), so use first element.
    final first = transactions.first;
    return DateTime.tryParse(first['payment_date']?.toString() ?? '');
  }

  // ===========================================================================
  // HISTORICAL PRINCIPAL & UNPAID ENTRIES
  // ===========================================================================

  /// Builds the unpaid entries list with *historical principal* logic.
  ///
  /// - [loan] : loan row from DB
  /// - [transactions] : txns for loan (any order; we sort ASC internally)
  /// - [dueDates] : all due dates up to now
  /// - [paidStatus] : bool list, true if that due slot is paid
  /// - [now] : current time
  ///
  /// Returns list like:
  /// {
  ///   'index': 1,
  ///   'due_date': DateTime,
  ///   'label': 'Jan 2025',
  ///   'principal_for_month': 100000.0,
  ///   'interest_for_month': 3000.0,
  /// }
  static List<Map<String, dynamic>> buildUnpaidEntriesList({
    required List<DateTime> dueDates,
    required List<bool> paidStatus,
    required DateTime now,
    required Map<String, dynamic> loan,
    required List<Map<String, dynamic>> transactions,
  }) {
    final List<Map<String, dynamic>> unpaidEntries = [];

    double currentPrincipal =
        (loan['original_principal'] as num?)?.toDouble() ??
            (loan['principal_amount'] as num?)?.toDouble() ??
            0.0;

    final double rate =
        (loan['interest_rate_percent'] as num?)?.toDouble() ?? 0.0;

    // Sort transactions ASC by payment date
    final txList = List<Map<String, dynamic>>.from(transactions);
    txList.sort((a, b) {
      final da = DateTime.tryParse(a['payment_date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db = DateTime.tryParse(b['payment_date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return da.compareTo(db);
    });

    int txIndex = 0;

    for (int i = 0; i < dueDates.length; i++) {
      final dueDate = dueDates[i];

      // Apply all principal payments up to this due date
      while (txIndex < txList.length) {
        final tx = txList[txIndex];
        final txDate = DateTime.tryParse(tx['payment_date']?.toString() ?? '');
        if (txDate == null || txDate.isAfter(dueDate)) break;

        final principalPaid =
            parseDouble(tx['principal_paid'], defaultValue: 0.0);
        if (principalPaid > 0) {
          currentPrincipal -= principalPaid;
          if (currentPrincipal < 0) currentPrincipal = 0;
        }

        txIndex++;
      }

      if (!paidStatus[i] && !dueDate.isAfter(now)) {
        final monthlyInterest = (currentPrincipal * rate) / 100;

        unpaidEntries.add({
          'index': i + 1,
          'due_date': dueDate,
          'label': monthLabel(dueDate),
          'principal_for_month': currentPrincipal,
          'interest_for_month': monthlyInterest,
        });
      }
    }

    return unpaidEntries;
  }

  /// Groups unpaid entries into segments by principal_for_month.
  ///
  /// Returns:
  /// [
  ///   {
  ///     'start_label':'Jan 2025',
  ///     'end_label':'Mar 2025',
  ///     'start_date': DateTime,
  ///     'end_date': DateTime,
  ///     'principal': 100000.0,
  ///     'monthly_interest': 3000.0,
  ///     'months_count': 3,
  ///     'total_interest': 9000.0
  ///   }, ...
  /// ]
  static List<Map<String, dynamic>> buildUnpaidSegments(
    List<Map<String, dynamic>> unpaidEntries,
  ) {
    if (unpaidEntries.isEmpty) return [];

    unpaidEntries.sort((a, b) {
      final da = a['due_date'] as DateTime?;
      final db = b['due_date'] as DateTime?;
      return (da ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(db ?? DateTime.fromMillisecondsSinceEpoch(0));
    });

    final List<Map<String, dynamic>> segments = [];
    Map<String, dynamic>? currentSegment;

    for (final entry in unpaidEntries) {
      final double principal =
          (entry['principal_for_month'] as num?)?.toDouble() ?? 0.0;
      final double monthlyInterest =
          (entry['interest_for_month'] as num?)?.toDouble() ?? 0.0;
      final String label = entry['label'] as String? ?? '';
      final DateTime dueDate = entry['due_date'] as DateTime;

      if (currentSegment == null) {
        currentSegment = {
          'start_label': label,
          'end_label': label,
          'start_date': dueDate,
          'end_date': dueDate,
          'principal': principal,
          'monthly_interest': monthlyInterest,
          'months_count': 1,
          'total_interest': monthlyInterest,
        };
      } else {
        final double segPrincipal =
            (currentSegment['principal'] as num?)?.toDouble() ?? 0.0;

        if (principal == segPrincipal) {
          currentSegment['end_label'] = label;
          currentSegment['end_date'] = dueDate;
          currentSegment['months_count'] =
              (currentSegment['months_count'] as int) + 1;
          currentSegment['total_interest'] =
              (currentSegment['total_interest'] as double) + monthlyInterest;
        } else {
          segments.add(currentSegment);
          currentSegment = {
            'start_label': label,
            'end_label': label,
            'start_date': dueDate,
            'end_date': dueDate,
            'principal': principal,
            'monthly_interest': monthlyInterest,
            'months_count': 1,
            'total_interest': monthlyInterest,
          };
        }
      }
    }

    if (currentSegment != null) {
      segments.add(currentSegment);
    }

    return segments;
  }

  /// Builds next due date object: { 'due_date': DateTime, 'label': String }
  static Map<String, dynamic> buildNextDueObject(
    DateTime startDate,
    int fixedDueDay,
    int dueCount,
  ) {
    final normalizedStart = normalizedStartDate(startDate, fixedDueDay);
    final nextDueDate = addMonths(normalizedStart, dueCount + 1);
    return {
      'due_date': nextDueDate,
      'label': monthLabel(nextDueDate),
    };
  }
}