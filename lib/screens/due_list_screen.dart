import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';

class DueListScreen extends StatefulWidget {
  const DueListScreen({super.key});

  @override
  State<DueListScreen> createState() => _DueListScreenState();
}

class _DueListScreenState extends State<DueListScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _reportData = [];

  final NumberFormat _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _generateReport();
  }

  // -------------------- DATE HELPERS --------------------

  DateTime _parseDate(String? value) {
    if (value == null || value.isEmpty) return DateTime.now();
    try {
      return DateTime.parse(value);
    } catch (_) {
      return DateTime.now();
    }
  }

  // Core rule:
  // Count how many FIXED DUE DATES have PASSED strictly before NOW
  int _countDuesPassed({
    required DateTime startDate,
    required int dueDay,
    required DateTime now,
  }) {
    int count = 0;

    // First due date candidate
    DateTime dueCursor = DateTime(startDate.year, startDate.month, dueDay);

    // If loan started AFTER that month's due, move to next month
    if (dueCursor.isBefore(startDate)) {
      dueCursor = DateTime(startDate.year, startDate.month + 1, dueDay);
    }

    // Count only dues that are strictly BEFORE now
    while (dueCursor.isBefore(now)) {
      count++;
      dueCursor = DateTime(dueCursor.year, dueCursor.month + 1, dueDay);
    }

    return count;
  }

  // -------------------- MAIN ENGINE --------------------

  Future<void> _generateReport() async {
    setState(() => _isLoading = true);

    try {
      final db = DatabaseHelper.instance;
      final loans = await db.getAllLoans();

      final DateTime now = DateTime.now();
      final List<Map<String, dynamic>> rows = [];

      for (final loan in loans) {
        final int loanId = loan['id'];
        final String status = loan['status'];

        final double principal =
            (loan['principal_amount'] as num).toDouble();
        final double rate =
            (loan['interest_rate_percent'] as num).toDouble();
        final int dueDay = loan['fixed_due_day'];

        // ✅ CORRECT ANCHOR
        final DateTime startDate =
            _parseDate(loan['start_date']);

        // ---------------- TRANSACTIONS ----------------

        final txns = await db.getLoanTransactions(loanId);

        int duesPaid = 0;
        double totalInterestReceived = 0;

        for (final t in txns) {
          duesPaid += (t['months_paid'] ?? 0) as int;
          totalInterestReceived +=
              (t['interest_paid'] ?? 0).toDouble();
        }

        // ---------------- CLOSED LOAN RULE ----------------
        if (status == 'closed') {
          rows.add({
            'name': loan['borrower_name'],
            'place': loan['borrower_place'],
            'start_date': startDate,
            'principal': principal,
            'rate': rate,
            'dues_passed': duesPaid,
            'dues_paid': duesPaid,
            'pending': 0,
            'total_interest': totalInterestReceived,
            'status': status,
          });
          continue;
        }

        // ---------------- DUE CALCULATION ----------------

        final int duesPassed = _countDuesPassed(
          startDate: startDate,
          dueDay: dueDay,
          now: now,
        );

        final int pending = duesPassed - duesPaid;

        rows.add({
          'name': loan['borrower_name'],
          'place': loan['borrower_place'],
          'start_date': startDate,
          'principal': principal,
          'rate': rate,
          'dues_passed': duesPassed,
          'dues_paid': duesPaid,
          'pending': pending,
          'total_interest': totalInterestReceived,
          'status': status,
        });
      }

      if (!mounted) return;
      setState(() {
        _reportData = rows;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Due list error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -------------------- UI --------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0.5,
        backgroundColor: Colors.white,
        title: const Text(
          'Master Due List',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reportData.isEmpty
              ? const Center(child: Text('No records found'))
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: const Color(0xFFF8FAFC),
                      child: Text(
                        'Generated on: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 24,
                            headingRowColor:
                                MaterialStateProperty.all(
                                    const Color(0xFFE2E8F0)),
                            border: TableBorder.all(
                              color: Colors.grey.shade300,
                            ),
                            columns: const [
                              DataColumn(label: Text('S.No')),
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('Place')),
                              DataColumn(label: Text('Start')),
                              DataColumn(label: Text('Principal')),
                              DataColumn(label: Text('Rate')),
                              DataColumn(label: Text('Passed')),
                              DataColumn(label: Text('Paid')),
                              DataColumn(
                                label: Text(
                                  'Pending',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                              DataColumn(label: Text('Interest Rec.')),
                            ],
                            rows: List.generate(_reportData.length, (i) {
                              final r = _reportData[i];
                              final int pending = r['pending'];

                              Color pendingColor = Colors.black;
                              if (pending > 0) pendingColor = Colors.red;
                              if (pending < 0) pendingColor = Colors.green;

                              return DataRow(
                                color:
                                    MaterialStateProperty.resolveWith(
                                  (states) => r['status'] == 'closed'
                                      ? Colors.grey.shade100
                                      : null,
                                ),
                                cells: [
                                  DataCell(Text('${i + 1}')),
                                  DataCell(Text(
                                    r['name'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  )),
                                  DataCell(Text(r['place'] ?? '-')),
                                  DataCell(Text(
                                    DateFormat('dd-MMM-yy')
                                        .format(r['start_date']),
                                  )),
                                  DataCell(Text(
                                      _currency.format(r['principal']))),
                                  DataCell(Text('${r['rate']}%')),
                                  DataCell(
                                      Center(child: Text('${r['dues_passed']}'))),
                                  DataCell(
                                      Center(child: Text('${r['dues_paid']}'))),
                                  DataCell(
                                    Center(
                                      child: Text(
                                        '$pending',
                                        style: TextStyle(
                                          color: pendingColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      _currency.format(r['total_interest']),
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
