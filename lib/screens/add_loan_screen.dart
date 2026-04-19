import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../ui/loan_ui.dart';

class AddLoanScreen extends StatefulWidget {
  const AddLoanScreen({super.key});

  @override
  State<AddLoanScreen> createState() => _AddLoanScreenState();
}

class _AddLoanScreenState extends State<AddLoanScreen> {
  final _formKey = GlobalKey<FormState>();

  // Borrower
  final _borrowerNameCtrl = TextEditingController();
  final _borrowerPlaceCtrl = TextEditingController();
  final _borrowerPhoneCtrl = TextEditingController();

  // Related person
  final _relatedTitleCtrl = TextEditingController();
  final _relatedNameCtrl = TextEditingController();
  final _relatedPhoneCtrl = TextEditingController();

  // Loan details
  final _principalCtrl = TextEditingController();
  final _interestCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _borrowerNameCtrl.dispose();
    _borrowerPlaceCtrl.dispose();
    _borrowerPhoneCtrl.dispose();
    _relatedTitleCtrl.dispose();
    _relatedNameCtrl.dispose();
    _relatedPhoneCtrl.dispose();
    _principalCtrl.dispose();
    _interestCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // BUSINESS LOGIC
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _handleDatePick() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: LoanTheme.primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: LoanTheme.textPrimary,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  String? _validateRequiredText(String? value, {String? fieldName}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Please enter ${fieldName ?? 'this field'}';
    }
    return null;
  }

  String? _validateAmount(String? value, {String label = 'amount'}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Please enter $label';

    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Please enter a valid number';
    if (parsed <= 0) return '$label must be greater than 0';

    return null;
  }

  String? _validateInterest(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Please enter interest rate';

    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Please enter a valid number';
    if (parsed < 0) return 'Interest rate cannot be negative';
    if (parsed > 100) return 'Interest seems too high. Please check again';

    return null;
  }

  String? _validatePhoneOptional(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null; // optional

    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 10) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  Future<void> _handleSaveLoan() async {
    FocusScope.of(context).unfocus(); // Close keyboard

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final principal = double.tryParse(_principalCtrl.text.trim()) ?? 0.0;
      final interestRate = double.tryParse(_interestCtrl.text.trim()) ?? 0.0;

      final loanData = {
        'loan_given_date': _selectedDate.toIso8601String(),
        'borrower_name': _borrowerNameCtrl.text.trim(),
        'borrower_place': _borrowerPlaceCtrl.text.trim(),
        'borrower_phone': _borrowerPhoneCtrl.text.trim(),
        'related_person_title': _relatedTitleCtrl.text.trim(),
        'related_person_name': _relatedNameCtrl.text.trim(),
        'related_person_phone': _relatedPhoneCtrl.text.trim(),
        'principal_amount': principal,
        'original_principal': principal,
        'interest_rate_percent': interestRate,
        'start_date': _selectedDate.toIso8601String(),
        'fixed_due_day': _selectedDate.day,
        'status': 'active',
        'notes': _notesCtrl.text.trim(),
      };

      final id = await DatabaseHelper.instance.insertLoan(loanData);

      if (!mounted) return;

      if (id <= 0) {
        _showSnackBar(
          'Failed to create loan. Please try again.',
          isError: true,
        );
        setState(() => _isSubmitting = false);
        return;
      }

      _showSnackBar('Loan created successfully!', isError: false);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        'Something went wrong. Please try again.',
        isError: true,
      );
      setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(message)),
          ],
        ),
        backgroundColor:
            isError ? LoanTheme.errorColor : LoanTheme.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // UI
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoanTheme.backgroundColor,
      appBar: _buildAppBar(),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildProgressHeader(),
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.all(LoanTheme.standardPadding),
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildBorrowerSection(),
                  const SizedBox(height: 24),
                  _buildRelatedPersonSection(),
                  const SizedBox(height: 24),
                  _buildLoanDetailsSection(),
                  const SizedBox(height: 32),
                  _buildSubmitButton(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: LoanTheme.backgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: LoanTheme.textPrimary,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Create New Loan',
        style: TextStyle(
          color: LoanTheme.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 20,
        ),
      ),
      centerTitle: false,
    );
  }

  Widget _buildProgressHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LoanTheme.headerGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Loan Application',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter borrower details',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── Sections ────────────────────────────────────────────────────────────────

  Widget _buildBorrowerSection() {
    return Column(
      children: [
        const LoanSectionHeader(
          title: 'Borrower Information',
          icon: Icons.person_outline_rounded,
        ),
        LoanTextField(
          controller: _borrowerNameCtrl,
          label: 'Full Name',
          hintText: 'Enter borrower name',
          isRequired: true,
          validator: (val) =>
              _validateRequiredText(val, fieldName: 'borrower name'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        LoanTextField(
          controller: _borrowerPlaceCtrl,
          label: 'Place / Address',
          hintText: 'Enter location',
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        LoanTextField(
          controller: _borrowerPhoneCtrl,
          label: 'Mobile Number',
          hintText: 'Enter phone number',
          keyboardType: TextInputType.phone,
          prefixIcon: Icons.phone_rounded,
          validator: _validatePhoneOptional,
          textInputAction: TextInputAction.next,
        ),
      ],
    );
  }

  Widget _buildRelatedPersonSection() {
    return Column(
      children: [
        const LoanSectionHeader(
          title: 'Related Person',
          subtitle: 'Broker / Guarantor / Reference',
          icon: Icons.contacts_outlined,
        ),
        LoanTextField(
          controller: _relatedTitleCtrl,
          label: 'Relation / Title',
          hintText: 'e.g., Broker, Guarantor',
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        LoanTextField(
          controller: _relatedNameCtrl,
          label: 'Full Name',
          hintText: 'Enter related person name',
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        LoanTextField(
          controller: _relatedPhoneCtrl,
          label: 'Mobile Number',
          hintText: 'Enter phone number',
          keyboardType: TextInputType.phone,
          prefixIcon: Icons.phone_rounded,
          validator: _validatePhoneOptional,
          textInputAction: TextInputAction.next,
        ),
      ],
    );
  }

  Widget _buildLoanDetailsSection() {
    return Column(
      children: [
        const LoanSectionHeader(
          title: 'Loan Details',
          icon: Icons.credit_card_rounded,
        ),
        LoanTextField(
          controller: _principalCtrl,
          label: 'Principal Amount',
          hintText: '0.00',
          prefixText: '₹ ',
          keyboardType: TextInputType.number,
          isRequired: true,
          validator: (val) =>
              _validateAmount(val, label: 'principal amount'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        LoanTextField(
          controller: _interestCtrl,
          label: 'Monthly Interest Rate',
          hintText: '0.0',
          suffixText: '% per month',
          keyboardType: TextInputType.number,
          isRequired: true,
          validator: _validateInterest,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _buildDatePicker(),
        const SizedBox(height: 12),
        LoanTextField(
          controller: _notesCtrl,
          label: 'Additional Notes',
          hintText: 'Any additional information...',
          maxLines: 3,
          textInputAction: TextInputAction.newline,
        ),
      ],
    );
  }

  Widget _buildDatePicker() {
    return Container(
      decoration: BoxDecoration(
        color: LoanTheme.cardColor,
        borderRadius: BorderRadius.circular(LoanTheme.borderRadius),
        border: Border.all(color: LoanTheme.borderColor),
      ),
      child: ListTile(
        onTap: _handleDatePick,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: LoanTheme.primaryColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.calendar_today_rounded,
            color: LoanTheme.primaryColor,
            size: 20,
          ),
        ),
        title: const Text(
          'Loan Given Date',
          style: TextStyle(
            color: LoanTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          DateFormat('dd MMMM yyyy').format(_selectedDate),
          style: const TextStyle(
            color: LoanTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: LoanTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: LoanTheme.headerGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: LoanTheme.buttonShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSubmitting ? null : _handleSaveLoan,
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: _isSubmitting ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.save_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Create Loan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isSubmitting)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
