import 'package:flutter/material.dart';

/// Centralized theme & shared widgets for loan-related screens.
class LoanTheme {
  // Brand Palette
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color secondaryColor = Color(0xFF8B5CF6);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  // Text Colors
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color successColor = Color(0xFF10B981);
  static const Color errorColor = Colors.red;

  // UI Elements
  static const Color borderColor = Color(0xFFE2E8F0);
  static const double borderRadius = 12.0;
  static const double standardPadding = 16.0;

  // Gradients & Shadows
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryColor, secondaryColor],
  );

  static final List<BoxShadow> softShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.02),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static final List<BoxShadow> buttonShadow = [
    BoxShadow(
      color: primaryColor.withOpacity(0.3),
      blurRadius: 15,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Section header used in loan screens (icon + title + optional subtitle).
class LoanSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  const LoanSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: LoanTheme.primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: LoanTheme.primaryColor, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: LoanTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: LoanTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Styled text field with label, required indicator, prefix/suffix, and validator.
class LoanTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final TextInputType? keyboardType;
  final String? prefixText;
  final String? suffixText;
  final IconData? prefixIcon;
  final int maxLines;
  final bool isRequired;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final void Function(String)? onFieldSubmitted;

  const LoanTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.keyboardType,
    this.prefixText,
    this.suffixText,
    this.prefixIcon,
    this.maxLines = 1,
    this.isRequired = false,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: LoanTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isRequired)
              const Text(
                ' *',
                style: TextStyle(
                  color: LoanTheme.errorColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: LoanTheme.cardColor,
            borderRadius: BorderRadius.circular(LoanTheme.borderRadius),
            border: Border.all(color: LoanTheme.borderColor),
            boxShadow: LoanTheme.softShadow,
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            maxLines: maxLines,
            style: const TextStyle(
              color: LoanTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: LoanTheme.textSecondary.withOpacity(0.6),
              ),
              prefixText: prefixText,
              suffixText: suffixText,
              prefixIcon: prefixIcon != null
                  ? Icon(prefixIcon, color: LoanTheme.textSecondary, size: 20)
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            validator: validator,
            onFieldSubmitted: onFieldSubmitted,
          ),
        ),
      ],
    );
  }
}
