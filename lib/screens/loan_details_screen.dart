import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';

// ==============================================================================
// 1. STYLE CONFIGURATION
// ==============================================================================

class DetailStyles {
  // Brand Palette
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color secondaryColor = Color(0xFF8B5CF6);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color dangerColor = Color(0xFFEF4444);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color borderColor = Color(0xFFE2E8F0);

  // Shadows & Decorations
  static final List<BoxShadow> softShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  static BoxDecoration cardDecoration = BoxDecoration(
    color: cardColor,
    borderRadius: BorderRadius.circular(16),
    boxShadow: softShadow,
  );
}

// ==============================================================================
// 2. MAIN SCREEN
// ==============================================================================

class LoanDetailsScreen extends StatefulWidget {
  final int loanId;
  const LoanDetailsScreen({super.key, required this.loanId});

  @override
  State<LoanDetailsScreen> createState() => _LoanDetailsScreenState();
}

class _LoanDetailsScreenState extends State<LoanDetailsScreen> {
  // --- Core Data State ---
  Map<String, dynamic>? _loan;
  List<Map<String, dynamic>> _transactions = [];

  // Unpaid entries with historical principal/interest per month
  List<Map<String, dynamic>> _unpaidEntries = [];
  DateTime? _nextFutureDue;

  bool _isLoading = true;

  // --- Interest / Selection State ---
  double _currentMonthInterest = 0.0; // Based on CURRENT principal
  int _selectedMonthCount = 0;        // How many earliest unpaid months are selected
  double _calculatedExpectedInterest = 0.0; // Sum of interest_for_month of selected entries

  // --- Payment Form State ---
  final _amountReceivedCtrl = TextEditingController();
  final _principalPaidCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _amountReceivedCtrl.dispose();
    _principalPaidCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ============================================================================ 
  // HELPERS (SAFE PARSING)
  // ============================================================================

  int _safeParseInt(dynamic value, {int defaultValue = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  double _safeParseDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  // ============================================================================ 
  // DATA & BUSINESS LOGIC
  // ============================================================================

  // Add this to _LoanDetailsScreenState
  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) return;
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    // Note: This requires the 'url_launcher' package in pubspec.yaml
    // import 'package:url_launcher/url_launcher.dart';
    // await launchUrl(launchUri);
    
    // For now, we print to console so the app doesn't crash if you haven't added the package yet
    debugPrint("Attempting to call: $phoneNumber"); 
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Calling $phoneNumber...')),
    );
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final db = DatabaseHelper.instance;

      // 1. Load Loan
      final loan = await db.getLoanById(widget.loanId);
      if (loan == null) {
        if (!mounted) return;
        _showFeedback('Loan not found', isError: true);
        Navigator.pop(context);
        return;
      }

      // 2. Load Transactions (for history list)
      final txnsDesc = await db.getLoanTransactions(widget.loanId);

      // 3. Load Unpaid Entries with historical principal/interest
      final unpaidInfo = await db.getLoanUnpaidEntries(widget.loanId);

      List<Map<String, dynamic>> unpaidEntries = [];
      DateTime? nextDue;

      if (unpaidInfo != null) {
        final rawEntries = unpaidInfo['unpaid_entries'];
        if (rawEntries is List) {
          unpaidEntries = rawEntries.cast<Map<String, dynamic>>();
        }

        final next = unpaidInfo['next_due'];
        if (next is Map && next['due_date'] is DateTime) {
          nextDue = next['due_date'] as DateTime;
        }
      }

      // Ensure unpaid entries sorted by due_date ascending (oldest first)
      unpaidEntries.sort((a, b) {
        final da = a['due_date'] as DateTime?;
        final dbDate = b['due_date'] as DateTime?;
        return (da ?? DateTime(0)).compareTo(dbDate ?? DateTime(0));
      });

      setState(() {
        _loan = loan;
        _transactions = txnsDesc;
        _unpaidEntries = unpaidEntries;
        _nextFutureDue = nextDue;
      });

      _performFinancialCalculations();
    } catch (e) {
      if (!mounted) return;
      _showFeedback('Error loading data: $e', isError: true);
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _performFinancialCalculations() {
    _resetFormState();

    if (_loan == null) return;

    // Current month interest (for helper display)
    final principal =
        _safeParseDouble(_loan!['principal_amount'], defaultValue: 0.0);
    final rate =
        _safeParseDouble(_loan!['interest_rate_percent'], defaultValue: 0.0);
    _currentMonthInterest = principal * (rate / 100);

    // Recalculate expected interest based on current selection (initially 0)
    _recalculateExpectedInterest();

    if (mounted) {
      setState(() {});
    }
  }

  void _resetFormState() {
    _selectedMonthCount = 0;
    _calculatedExpectedInterest = 0.0;
    _amountReceivedCtrl.clear();
    _principalPaidCtrl.clear();
    _notesCtrl.clear();
  }

  void _recalculateExpectedInterest() {
    double total = 0.0;

    for (int i = 0;
        i < _selectedMonthCount && i < _unpaidEntries.length;
        i++) {
      final entry = _unpaidEntries[i];
      final monthInterest =
          _safeParseDouble(entry['interest_for_month'], defaultValue: 0.0);
      total += monthInterest;
    }

    _calculatedExpectedInterest = total;

    // Requirement: "In interest received field it should add value based on selected months interest"
    // We update the text field whenever selection changes
    if (_selectedMonthCount > 0) {
      _amountReceivedCtrl.text = _calculatedExpectedInterest.toStringAsFixed(0);
    } else {
      // If no months selected, user might be paying just principal or custom interest, so we clear it
      _amountReceivedCtrl.clear();
    }
  }

  // --- Interaction Handlers ---

  void _handleMonthSelection(int index) {
    if (_unpaidEntries.isEmpty) return;

    setState(() {
      final alreadySelectingExactlyThis =
          (_selectedMonthCount == index + 1);

      if (alreadySelectingExactlyThis) {
        // Tapping the last selected → clear all
        _selectedMonthCount = 0;
      } else {
        // Select from 0..index
        _selectedMonthCount = index + 1;
      }

      _recalculateExpectedInterest();
    });
  }

  Future<void> _handlePaymentSubmission() async {
    if (_loan == null) return;

    final double rawPrincipalPaid = _safeParseDouble(
      _principalPaidCtrl.text.replaceAll(',', ''),
      defaultValue: 0.0,
    );
    final double interestPaid = _safeParseDouble(
      _amountReceivedCtrl.text.replaceAll(',', ''),
      defaultValue: 0.0,
    );

    // At least one: month selection OR principal
    if (_selectedMonthCount == 0 && rawPrincipalPaid <= 0 && interestPaid <= 0) {
      _showFeedback(
        'Enter payment details (Interest or Principal)',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final double currentPrincipal =
          _safeParseDouble(_loan!['principal_amount'], defaultValue: 0.0);

      // Prevent negative principal: clamp paid principal to currentPrincipal
      final double principalPaid = rawPrincipalPaid > currentPrincipal
          ? currentPrincipal
          : rawPrincipalPaid;

      final double newPrincipal =
          (currentPrincipal - principalPaid).clamp(0.0, double.infinity);

      String note = _notesCtrl.text.trim();
      if (note.isEmpty && principalPaid > 0) {
        note =
            'Principal reduced by ${_currencyFormat.format(principalPaid)}';
      }

      final nowIso = DateTime.now().toIso8601String();

      final transactionData = {
        'loan_id': widget.loanId,
        'payment_date': nowIso,
        'months_paid': _selectedMonthCount,
        'interest_paid': interestPaid,
        'principal_paid': principalPaid,
        'new_principal_balance': newPrincipal,
        'notes': note,
        'created_at': nowIso,
      };

      await DatabaseHelper.instance.insertTransaction(transactionData);

      // Reload everything with updated history & unpaid entries
      await _fetchData();
      if (!mounted) return;
      _showFeedback('Payment recorded successfully!');
    } catch (e) {
      if (!mounted) return;
      _showFeedback('Error saving payment: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCloseAccount() async {
    if (_loan == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Close Loan Account"),
        content: const Text(
          "Are you sure? This marks the loan as settled and prevents further payments.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DetailStyles.dangerColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Close Account",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await DatabaseHelper.instance.closeLoan(widget.loanId);
      await _fetchData();
      if (!mounted) return;
      _showFeedback('Loan account closed successfully!');
    } catch (e) {
      if (!mounted) return;
      _showFeedback('Error closing loan: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  void _showFeedback(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: isError ? DetailStyles.dangerColor : DetailStyles.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  // ============================================================================ 
  // UI
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final borrowerName = _loan?['borrower_name'] ?? 'Loan Details';

    return Scaffold(
      backgroundColor: DetailStyles.backgroundColor,
      appBar: AppBar(
        backgroundColor: DetailStyles.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: DetailStyles.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          borrowerName,
          style: const TextStyle(
            color: DetailStyles.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ),
      body: _isLoading
          ? _buildLoadingState()
          : RefreshIndicator(
              color: DetailStyles.primaryColor,
              onRefresh: _fetchData,
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  if (_loan != null)
                    _HeaderSection(
                      loan: _loan!,
                      unpaidCount: _unpaidEntries.length,
                      onCloseTap: _handleCloseAccount,
                      onCallTap: _makePhoneCall,
                    ),
                  if (_loan != null) _InfoSection(loan: _loan!,onCallTap: _makePhoneCall,),
                  if (_loan != null)
                    _PaymentSection(
                      loan: _loan!,
                      unpaidEntries: _unpaidEntries,
                      selectedCount: _selectedMonthCount,
                      currentMonthInterest: _currentMonthInterest,
                      amountCtrl: _amountReceivedCtrl,
                      principalCtrl: _principalPaidCtrl,
                      notesCtrl: _notesCtrl,
                      expectedInterest: _calculatedExpectedInterest,
                      onMonthSelect: _handleMonthSelection,
                      onSubmit: _handlePaymentSubmission,
                    ),
                  if (_nextFutureDue != null && _unpaidEntries.isEmpty)
                    _buildAllClearBanner(),
                  _TransactionHistorySection(transactions: _transactions),
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(DetailStyles.primaryColor),
          ),
          SizedBox(height: 16),
          Text(
            'Loading details...',
            style: TextStyle(color: DetailStyles.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildAllClearBanner() {
    if (_nextFutureDue == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DetailStyles.successColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DetailStyles.successColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: DetailStyles.successColor,
            size: 28,
          ),
          const SizedBox(height: 8),
          const Text(
            'All past dues cleared!',
            style: TextStyle(
              color: DetailStyles.successColor,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Next due: ${DateFormat('MMMM yyyy').format(_nextFutureDue!)}',
            style: const TextStyle(
              color: DetailStyles.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// 3. UPDATED SUB-WIDGETS (Header & Info)
// ==============================================================================
class _HeaderSection extends StatelessWidget {
  final Map<String, dynamic> loan;
  final int unpaidCount;
  final VoidCallback onCloseTap;
  final Function(String) onCallTap;

  const _HeaderSection({
    required this.loan,
    required this.unpaidCount,
    required this.onCloseTap,
    required this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isClosed = (loan['status'] ?? 'active') == 'closed';
    final String name = (loan['borrower_name'] ?? 'Unknown') as String;
    final String place = (loan['borrower_place'] ?? '') as String;
    final String phone = (loan['borrower_phone'] ?? '') as String;

    final Color primaryColor =
        isClosed ? Colors.grey : DetailStyles.primaryColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name + Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color:
                              isClosed ? Colors.grey : Colors.black87,
                        ),
                      ),
                    ),
                    _buildStatusBadge(isClosed, unpaidCount),
                  ],
                ),

                if (place.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    place,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ],

                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => onCallTap(phone),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.call,
                            size: 14, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          phone,
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (!isClosed)
            InkWell(
              onTap: onCloseTap,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.lock_outline,
                  size: 20,
                  color: Colors.grey,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool isClosed, int unpaidCount) {
    final String text = isClosed
        ? 'Closed'
        : (unpaidCount > 0 ? '$unpaidCount Due' : 'Active');

    final Color color = isClosed
        ? Colors.grey
        : (unpaidCount > 0
            ? DetailStyles.dangerColor
            : DetailStyles.successColor);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final Map<String, dynamic> loan;
  final Function(String) onCallTap;

  const _InfoSection({
    required this.loan,
    required this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    final formatter =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    final double principal =
        (loan['principal_amount'] as num?)?.toDouble() ?? 0.0;
    final double originalPrincipal =
        (loan['original_principal'] as num?)?.toDouble() ?? 0.0;

    // ✅ CORRECT DATE: START DATE (NOT GIVEN DATE)
    final String startDateStr = loan['start_date'] ?? '';
    final DateTime? startDate = DateTime.tryParse(startDateStr);
    final String formattedStartDate = startDate != null
        ? DateFormat('dd MMM yyyy').format(startDate)
        : '-';

    final String relationTitle = loan['related_person_title'] ?? ''; // e.g. "Father"
    final String relationName = loan['related_person_name'] ?? '';
    final String relationPhone = loan['related_person_phone'] ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        children: [
          // Principal Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Current Principal",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatter.format(principal),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Text(
                "Original: ${formatter.format(originalPrincipal)}",
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 16),

          // Loan Meta
          Row(
            children: [
              _InfoTile("Rate", "${loan['interest_rate_percent']}%"),
              _InfoTile("Due Day", "${loan['fixed_due_day']}th"),
              _InfoTile("Start", formattedStartDate),
            ],
          ),

          if (relationName.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 16),

            Row(
              children: [
                // Icon
                const Icon(Icons.people_outline, size: 18, color: DetailStyles.textSecondary),
                const SizedBox(width: 10),
                
                // Name & Title
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // If title exists (e.g. "Father"), uppercase it. Else default to "RELATION"
                        relationTitle.isNotEmpty ? relationTitle.toUpperCase() : "RELATION",
                        style: const TextStyle(
                          fontSize: 11,
                          color: DetailStyles.textSecondary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        relationName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: DetailStyles.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Phone (Clickable)
                if (relationPhone.isNotEmpty)
                  InkWell(
                    onTap: () => onCallTap(relationPhone),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        relationPhone,
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.blue,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
// ...existing code...
class _InfoTile extends StatelessWidget {
  final String title;
  final String value;

  const _InfoTile(this.title, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
// ...existing code...



// ==============================================================================
// 4. REWRITTEN PAYMENT SECTION (Grouped Timeline)
// ==============================================================================

class _PaymentSection extends StatelessWidget {
  final Map<String, dynamic> loan;
  final List<Map<String, dynamic>> unpaidEntries;
  final int selectedCount;
  final double currentMonthInterest;
  final TextEditingController amountCtrl;
  final TextEditingController principalCtrl;
  final TextEditingController notesCtrl;
  final double expectedInterest;
  final ValueChanged<int> onMonthSelect;
  final VoidCallback onSubmit;

  const _PaymentSection({
    required this.loan,
    required this.unpaidEntries,
    required this.selectedCount,
    required this.currentMonthInterest,
    required this.amountCtrl,
    required this.principalCtrl,
    required this.notesCtrl,
    required this.expectedInterest,
    required this.onMonthSelect,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    if (loan['status'] == 'closed') return const SizedBox.shrink();

    // 1. Group the months by Principal
    final List<Map<String, dynamic>> groupedMonths = _groupMonthsByPrincipal();

    // Calculate diff for validation warning
    final double received = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0.0;
    final double diff = received - expectedInterest;
    final bool showWarning = selectedCount > 0 && diff < -1.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: DetailStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- HEADER: Payment Section ---
          const Text(
            'Payment Section',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: DetailStyles.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          // --- BLOCK 1: Current Month Interest ---
          Center(
            child: Column(
              children: [
                const Text(
                  'CURRENT MONTH INTEREST',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DetailStyles.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${currentMonthInterest.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: DetailStyles.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),

          // --- BLOCK 2: The Timeline (Unpaid Months) ---
          if (unpaidEntries.isNotEmpty) ...[
            const Text(
              'UNPAID MONTHS:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DetailStyles.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            
            // Loop through groups and render timeline
            ..._buildTimeline(groupedMonths),

            if (selectedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: Text(
                    'Total for selected: ₹${expectedInterest.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: DetailStyles.primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 30),
          ],

          // --- BLOCK 3: Inputs (Sketch Style) ---
          const Text(
            'Interest Received',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DetailStyles.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _SketchyInput(
            controller: amountCtrl,
            hint: '₹ 0',
            helperText: selectedCount > 0 ? 'Autofilled based on selected months' : null,
          ),
          
          const SizedBox(height: 16),
          
          const Text(
            'Principal',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DetailStyles.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _SketchyInput(
            controller: principalCtrl,
            hint: '₹ 0',
          ),

          const SizedBox(height: 16),
          
          const Text(
            'Notes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DetailStyles.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _SketchyInput(
            controller: notesCtrl,
            hint: '',
            isNote: true,
          ),

          // Warning if underpaying
          if (showWarning)
             Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: DetailStyles.dangerColor),
                  const SizedBox(width: 8),
                  Text(
                    'Short by ₹${diff.abs().toStringAsFixed(0)}',
                    style: const TextStyle(color: DetailStyles.dangerColor, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 30),
          
          // Submit Button (Handwritten style label)
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: DetailStyles.primaryColor,
                foregroundColor: Colors.white,
                elevation: 8,
                shadowColor: DetailStyles.primaryColor.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.check_circle_rounded, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Confirm Payment',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Logic to Group Months by Principal ---
  List<Map<String, dynamic>> _groupMonthsByPrincipal() {
    List<Map<String, dynamic>> groups = [];
    if (unpaidEntries.isEmpty) return [];

    double currentPrincipal = -1;
    List<Map<String, dynamic>> currentList = [];

    for (var entry in unpaidEntries) {
      // 1. Get principal for this specific historical month
      // (Assuming your query returns 'principal_amount' snapshot for that month. 
      // If not available, we use current loan principal as fallback)
      double p = double.tryParse(entry['historical_principal']?.toString() ?? '') 
          ?? double.tryParse(loan['principal_amount'].toString()) ?? 0.0;

      if (p != currentPrincipal) {
        if (currentList.isNotEmpty) {
          groups.add({'principal': currentPrincipal, 'entries': currentList});
        }
        currentPrincipal = p;
        currentList = [entry];
      } else {
        currentList.add(entry);
      }
    }
    // Add the last bunch
    if (currentList.isNotEmpty) {
      groups.add({'principal': currentPrincipal, 'entries': currentList});
    }
    return groups;
  }

  // --- Render the Timeline ---
  List<Widget> _buildTimeline(List<Map<String, dynamic>> groupedMonths) {
    List<Widget> widgets = [];
    int globalIndex = 0; // To track selection index across groups

    for (int i = 0; i < groupedMonths.length; i++) {
      final group = groupedMonths[i];
      final double principal = group['principal'] as double;
      final List<Map<String, dynamic>> entries = group['entries'];
      
      final bool isFirstGroup = (i == 0);
      final String label = isFirstGroup 
          ? 'ORIGINAL PRINCIPAL ₹${principal.toInt()}'
          : 'PRINCIPAL CHANGED TO ₹${principal.toInt()}'; // As per your sketch

      // 1. The Line Divider
      widgets.add(
        _PrincipalDivider(label: label),
      );

      // 2. The Boxes (Wrap)
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: entries.map((entry) {
              final int myIndex = globalIndex++;
              final bool isSelected = myIndex < selectedCount;
              
              final DateTime? dueDate = entry['due_date'] is DateTime 
                  ? entry['due_date'] 
                  : DateTime.tryParse(entry['due_date'].toString());
                  
              final String monthName = dueDate != null 
                  ? DateFormat('MMM').format(dueDate).toUpperCase() 
                  : 'M${myIndex + 1}';

              return _MonthBox(
                label: monthName,
                isSelected: isSelected,
                onTap: () => onMonthSelect(myIndex),
              );
            }).toList(),
          ),
        ),
      );
    }
    return widgets;
  }
}

// --- Helper Widget: The Divider Line with Text ---
class _PrincipalDivider extends StatelessWidget {
  final String label;
  const _PrincipalDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: DetailStyles.textPrimary, thickness: 1.5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: DetailStyles.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const Expanded(child: Divider(color: DetailStyles.textPrimary, thickness: 1.5)),
      ],
    );
  }
}

// --- Helper Widget: The Month Box ([ JAN ]) ---
class _MonthBox extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MonthBox({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.transparent, // Transparent to look like sketch
          border: Border.all(
            color: isSelected ? DetailStyles.primaryColor : DetailStyles.textPrimary,
            width: isSelected ? 2.5 : 1.5,
          ),
          // Slight distinct look for selected
          boxShadow: isSelected 
              ? [BoxShadow(color: DetailStyles.primaryColor.withOpacity(0.2), blurRadius: 8)] 
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isSelected ? DetailStyles.primaryColor : DetailStyles.textPrimary,
          ),
        ),
      ),
    );
  }
}

// --- Helper Widget: Sketch Style Input Field ---
class _SketchyInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool isNote;
  final String? helperText;

  const _SketchyInput({
    required this.controller,
    required this.hint,
    this.isNote = false,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: DetailStyles.textPrimary, width: 1.5),
            // No border radius to make it look like a sharp box
          ),
          child: TextField(
            controller: controller,
            keyboardType: isNote ? TextInputType.text : TextInputType.number,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              isDense: true,
            ),
          ),
        ),
        if (helperText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              helperText!,
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 12,
                color: DetailStyles.textSecondary,
              ),
            ),
          )
      ],
    );
  }
}

// ==============================================================================
// 5. REWRITTEN HISTORY SECTION (Pagination: 3 Items + Original Card Style)
// ==============================================================================

class _TransactionHistorySection extends StatefulWidget {
  final List<Map<String, dynamic>> transactions;
  final Map<String, dynamic>? loan;

  const _TransactionHistorySection({
    required this.transactions,
    this.loan,
  });

  @override
  State<_TransactionHistorySection> createState() => _TransactionHistorySectionState();
}

class _TransactionHistorySectionState extends State<_TransactionHistorySection> {
  // Pagination State
  int _currentPage = 0;
  
  // CHANGED: Set to 3 items per page
  final int _itemsPerPage = 3; 

  @override
  Widget build(BuildContext context) {
    // 1. Prepare Full List
    final List<Map<String, dynamic>> fullHistory = _prepareHistoryList();
    
    // 2. Calculate Pagination
    final int totalItems = fullHistory.length;
    final int totalPages = (totalItems / _itemsPerPage).ceil();
    
    // Safety check if pages reduce (e.g. deletion)
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }

    // 3. Slice list for current page
    final int startIndex = _currentPage * _itemsPerPage;
    final int endIndex = (startIndex + _itemsPerPage < totalItems) 
        ? startIndex + _itemsPerPage 
        : totalItems;
        
    final List<Map<String, dynamic>> currentParams = 
        (totalItems > 0) ? fullHistory.sublist(startIndex, endIndex) : [];

    if (fullHistory.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header showing total count
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0, left: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                 Row(
                  children: [
                    const Icon(Icons.history, color: DetailStyles.textPrimary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Full History ($totalItems)',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: DetailStyles.textPrimary),
                    ),
                  ],
                ),
                 if (totalItems > 0)
                  Text(
                    'Showing ${startIndex + 1}-$endIndex',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
          
          // --- The Timeline List ---
          if (currentParams.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text("No history found.")),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: currentParams.length,
              itemBuilder: (ctx, index) {
                final item = currentParams[index];
                // Check if this is the absolute last item on the current page to hide connector
                final bool isLastOnPage = index == currentParams.length - 1;
                return _TimelineItem(item: item, isLast: isLastOnPage);
              },
            ),

          // --- Pagination Controls ---
          if (totalPages > 1) ...[
            const SizedBox(height: 16),
            _buildPaginationControls(totalPages),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  // Helper: Prepare merged list
  List<Map<String, dynamic>> _prepareHistoryList() {
    final List<Map<String, dynamic>> historyItems = [];

    // Add Creation Event
    if (widget.loan != null) {
      final String dateStr = widget.loan!['given_date'] ?? widget.loan!['created_at'] ?? '';
      final double originalPrincipal = (widget.loan!['original_principal'] as num?)?.toDouble() ?? 0.0;
      
      historyItems.add({
        'type': 'creation',
        'date': dateStr,
        'amount': originalPrincipal,
        'notes': 'Loan Disbursed successfully.',
      });
    }

    // Add Payments
    for (var t in widget.transactions) {
      historyItems.add({
        'type': 'payment',
        'id': t['id'],
        'date': t['payment_date'],
        'interest': (t['interest_paid'] as num?)?.toDouble() ?? 0.0,
        'principal': (t['principal_paid'] as num?)?.toDouble() ?? 0.0,
        'months_count': (t['months_paid'] as int?) ?? 0,
        // Shows "JAN, FEB" if available in DB
        'month_labels': t['month_labels_snapshot'] ?? '', 
        'notes': t['notes'],
      });
    }

    // Sort Newest First
    historyItems.sort((a, b) {
      final da = DateTime.tryParse(a['date'].toString()) ?? DateTime(2000);
      final db = DateTime.tryParse(b['date'].toString()) ?? DateTime(2000);
      return db.compareTo(da);
    });

    return historyItems;
  }

  // Helper: Build pagination buttons
  Widget _buildPaginationControls(int totalPages) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
          icon: Icon(Icons.chevron_left_rounded, color: _currentPage > 0 ? DetailStyles.textPrimary : Colors.grey.shade300),
        ),
        ..._buildPageNumbers(totalPages),
        IconButton(
          onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
          icon: Icon(Icons.chevron_right_rounded, color: _currentPage < totalPages - 1 ? DetailStyles.textPrimary : Colors.grey.shade300),
        ),
      ],
    );
  }

  List<Widget> _buildPageNumbers(int totalPages) {
    List<Widget> pages = [];
    if (totalPages <= 5) {
      for (int i = 0; i < totalPages; i++) pages.add(_buildPageButton(i));
    } else {
      pages.add(_buildPageButton(0));
      if (_currentPage > 2) pages.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text("...")));
      final int start = (_currentPage - 1).clamp(1, totalPages - 2);
      final int end = (_currentPage + 1).clamp(1, totalPages - 2);
      for (int i = start; i <= end; i++) pages.add(_buildPageButton(i));
      if (_currentPage < totalPages - 3) pages.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text("...")));
      pages.add(_buildPageButton(totalPages - 1));
    }
    return pages;
  }

  Widget _buildPageButton(int index) {
    final bool isActive = index == _currentPage;
    return GestureDetector(
      onTap: () => setState(() => _currentPage = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: isActive ? DetailStyles.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive ? null : Border.all(color: Colors.grey.shade300),
        ),
        child: Center(child: Text('${index + 1}', style: TextStyle(color: isActive ? Colors.white : DetailStyles.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
      ),
    );
  }
}

// ==============================================================================
// THE TIMELINE ITEM (RESTORED TO ORIGINAL STYLE)
// ==============================================================================
class _TimelineItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isLast;

  const _TimelineItem({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final bool isCreation = item['type'] == 'creation';
    final String dateStr = item['date']?.toString() ?? '';
    final DateTime date = DateTime.tryParse(dateStr) ?? DateTime.now();
    
    final String dayTime = DateFormat('dd MMM yyyy • hh:mm a').format(date);
    final NumberFormat currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    final double interest = item['interest'] ?? 0.0;
    final double principal = item['principal'] ?? 0.0;
    final int monthsCount = item['months_count'] ?? 0;
    final String monthLabels = item['month_labels']?.toString() ?? '';
    final String notes = item['notes']?.toString() ?? '';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Timeline Connector
          Column(
            children: [
              Container(
                width: 14, height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: isCreation ? DetailStyles.primaryColor : DetailStyles.textSecondary, width: 2),
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: Colors.grey.shade200)),
            ],
          ),
          const SizedBox(width: 16),

          // 2. The Card Content (Restored Style)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date Header
                  Text(dayTime, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                  const SizedBox(height: 8),

                  // The Card Box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with Icon
                        Row(
                          children: [
                            Icon(isCreation ? Icons.account_balance_wallet : Icons.payment, size: 18, color: DetailStyles.textPrimary),
                            const SizedBox(width: 8),
                            Text(
                              isCreation ? 'LOAN DISBURSED' : 'PAYMENT RECEIVED',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DetailStyles.textPrimary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),

                        // Financial Details
                        if (isCreation)
                           _buildRow('Original Amount', currency.format(item['amount']), isBold: true),

                        if (!isCreation) ...[
                          if (interest > 0)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildRow('Interest Paid', currency.format(interest), color: DetailStyles.successColor, isBold: true),
                                // Month details (Count OR Names)
                                if (monthsCount > 0 || monthLabels.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2, bottom: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (monthsCount > 0)
                                          Text('(Paid for $monthsCount Months)', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade600)),
                                        // Specific Month Names (e.g., JAN, FEB)
                                        if (monthLabels.isNotEmpty)
                                           Text('[$monthLabels]', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          
                          if (principal > 0)
                            _buildRow('Principal Reduced', currency.format(principal), isBold: true, color: DetailStyles.primaryColor),
                        ],

                        // Notes Box (Restored Style)
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade100),
                            ),
                            child: Text(
                              '"$notes"',
                              style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: DetailStyles.textSecondary)),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: isBold ? FontWeight.w700 : FontWeight.w600, color: color ?? DetailStyles.textPrimary)),
        ],
      ),
    );
  }
}