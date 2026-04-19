import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import 'loan_details_screen.dart';
import 'add_loan_screen.dart'; 
import 'due_list_screen.dart'; 

// ==============================================================================
// 1. DASHBOARD THEME
// ==============================================================================
class DashTheme {
  static const Color bgColor = Color(0xFFF8FAFC);
  static const Color darkBlue = Color(0xFF1E293B);
  static const Color primary = Color(0xFF6366F1);
  static const Color cardColor = Colors.white;
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);

  static final List<BoxShadow> softShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];
  
  static final List<BoxShadow> buttonShadow = [
    BoxShadow(
      color: primary.withOpacity(0.3),
      blurRadius: 12,
      offset: const Offset(0, 6),
    ),
  ];

  static const LinearGradient headerGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ==============================================================================
// 2. MAIN DASHBOARD SCREEN
// ==============================================================================

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // --- State ---
  List<Map<String, dynamic>> _allLoans = [];
  bool _isLoading = true;
  String _searchQuery = '';
  
  // FIX 1: Add a specific FocusNode to control the keyboard
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  // --- Derived State ---
  List<Map<String, dynamic>> get _filteredLoans {
    // 1. Base Filter: Active Loans first, then Closed
    final activeLoans = _allLoans.where((l) => (l['status'] ?? 'active') == 'active');
    final closedLoans = _allLoans.where((l) => (l['status'] ?? 'active') == 'closed');
    
    final combined = [...activeLoans, ...closedLoans];

    // 2. Apply Search Filter
    if (_searchQuery.isEmpty) {
      return combined;
    }

    return combined.where((loan) {
      final name = (loan['borrower_name'] ?? '').toString().toLowerCase();
      final place = (loan['borrower_place'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || place.contains(query);
    }).toList();
  }

  double get _totalPrincipal {
    // Calculate total only for active loans
    return _allLoans
        .where((l) => (l['status'] ?? 'active') == 'active')
        .fold<double>(0.0, (sum, item) {
          final value = item['principal_amount'];
          if (value is num) return sum + value.toDouble();
          return sum;
        });
  }

  int get _overdueCount {
    return _allLoans
        .where((l) => (l['status'] ?? 'active') == 'active')
        .where((l) => (l['unpaid_months'] as int? ?? 0) > 0)
        .length;
  }

  int get _activeCount {
    return _allLoans
        .where((l) => (l['status'] ?? 'active') == 'active')
        .length;
  }

  @override
  void initState() {
    super.initState();
    _loadLoans();
  }

  @override
  void dispose() {
    _searchController.dispose();
    // FIX 2: Dispose the focus node
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ========================================================================
  // DATA LOADING
  // ========================================================================

  Future<void> _loadLoans() async {
    try {
      setState(() => _isLoading = true);
      final loans = await DatabaseHelper.instance.getAllLoans();

      // Compute due status for each loan
      final futures = loans.map((loan) async {
        final due = await DatabaseHelper.instance.getLoanDueStatus(loan['id'] as int);
        return {
          ...loan,
          'unpaid_months': due?['unpaid_months'] ?? 0,
          'last_paid': due?['last_paid'],
        };
      });

      final processed = await Future.wait(futures);

      if (!mounted) return;
      setState(() {
        _allLoans = processed;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading loans: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========================================================================
  // NAVIGATION
  // ========================================================================

  void _navigateToDueList() {
    Navigator.push(
      context, 
      MaterialPageRoute(builder: (context) => const DueListScreen())
    );
  }

  // ========================================================================
  // UI
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashTheme.bgColor,
      appBar: _buildAppBar(),
      floatingActionButton: _buildFloatingActionButton(),
      // Use GestureDetector to unfocus if user taps anywhere on background
      body: GestureDetector(
        onTap: () {
          if (_searchFocusNode.hasFocus) _searchFocusNode.unfocus();
        },
        child: Column(
          children: [
            _buildWealthCard(),
            _buildSearchBar(),
            Expanded(child: _buildMainContent()),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: DashTheme.bgColor,
      elevation: 0,
      centerTitle: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Loan Manager',
            style: TextStyle(
              color: DashTheme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          Text(
            'Overview',
            style: TextStyle(
              color: DashTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        // DUE LIST BUTTON
        Padding(
          padding: const EdgeInsets.only(right: 16.0, top: 10, bottom: 10),
          child: ElevatedButton.icon(
            onPressed: _navigateToDueList,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: DashTheme.primary,
              elevation: 0,
              side: const BorderSide(color: DashTheme.primary, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.list_alt_rounded, size: 18),
            label: const Text(
              "Due List",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWealthCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: DashTheme.headerGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: DashTheme.buttonShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Outstanding',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _currencyFormat.format(_totalPrincipal),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildMiniStat('Active Loans', '$_activeCount'),
              Container(
                height: 30, 
                width: 1, 
                color: Colors.white.withOpacity(0.3), 
                margin: const EdgeInsets.symmetric(horizontal: 24)
              ),
              _buildMiniStat('Overdue', '$_overdueCount', isWarning: _overdueCount > 0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, {bool isWarning = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: isWarning ? const Color(0xFFFF8A80) : Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: DashTheme.softShadow,
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode, // FIX 3: Attach the specific focus node
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          decoration: InputDecoration(
            hintText: "Search by borrower name...",
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
            suffixIcon: _searchQuery.isNotEmpty 
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    // Also clear focus when clearing text
                    _searchFocusNode.unfocus();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(DashTheme.primary),
        ),
      );
    }

    if (_filteredLoans.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      physics: const BouncingScrollPhysics(),
      itemCount: _filteredLoans.length,
      itemBuilder: (context, index) {
        return _buildLoanCard(_filteredLoans[index]);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'No result found' : 'No Loans Found',
            style: const TextStyle(
              color: DashTheme.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoanCard(Map<String, dynamic> loan) {
    final int unpaid = loan['unpaid_months'] as int? ?? 0;
    final bool isOverdue = unpaid > 0;
    final bool isCritical = unpaid >= 3;
    final String borrowerName = loan['borrower_name'] as String? ?? 'Unknown';
    final String place = loan['borrower_place'] as String? ?? '';
    final bool isClosed = (loan['status'] ?? 'active') == 'closed';
    final double principal = (loan['principal_amount'] as num?)?.toDouble() ?? 0.0;

    final Color statusColor = isClosed
        ? Colors.grey
        : isOverdue
            ? (isCritical ? DashTheme.danger : DashTheme.warning)
            : DashTheme.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              // FIX 4: Explicitly Unfocus BEFORE Navigation
              // This is the key line that stops the keyboard from reopening
              if (_searchFocusNode.hasFocus) {
                _searchFocusNode.unfocus();
              }
              // Backup generic unfocus for safety
              FocusScope.of(context).unfocus();

              final res = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LoanDetailsScreen(loanId: loan['id'] as int),
                ),
              );
              if (res == true || res == null) {
                _loadLoans();
              }
            },
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Header Row
                      Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: isClosed 
                                  ? Colors.grey.shade100 
                                  : DashTheme.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                borrowerName.isNotEmpty ? borrowerName[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: isClosed ? Colors.grey : DashTheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              borrowerName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isClosed ? Colors.grey : DashTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (!isClosed)
                            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      Divider(height: 1, color: Colors.grey.shade100),
                      const SizedBox(height: 12),

                      // Data Rows
                      _buildCardRow('Principal', 
                        isClosed ? 'Settled' : _currencyFormat.format(principal), 
                        isBold: true
                      ),
                      if (place.isNotEmpty)
                        _buildCardRow('Place', place),
                      
                      if (!isClosed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Status',
                                style: TextStyle(fontSize: 13, color: DashTheme.textSecondary),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isOverdue ? '$unpaid Month(s) Due' : 'Active',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Diagonal Badge for Closed Loans
                if (isClosed)
                  Positioned(
                    top: 15,
                    right: -28,
                    child: Transform.rotate(
                      angle: 0.785, // 45 degrees
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 4),
                        decoration: BoxDecoration(
                          color: DashTheme.danger,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 3,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: const Text(
                          'CLOSED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: DashTheme.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              color: DashTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return FloatingActionButton(
      onPressed: () async {
        final result = await Navigator.pushNamed(context, '/addLoan') as bool?;
        if (result == true) _loadLoans();
      },
      backgroundColor: DashTheme.primary,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Icon(Icons.add, color: Colors.white, size: 28),
    );
  }
}