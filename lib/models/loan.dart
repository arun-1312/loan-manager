class Loan {
  int? id;
  String borrowerName;
  String? borrowerPhone;
  String? borrowerPlace;
  int? brokerId;
  double principalAmount;
  double? interestRatePercent;
  String? startDate;
  double? monthlyInterest;
  String? loanType;
  String? notes;
  String status;

  Loan({
    this.id,
    required this.borrowerName,
    this.borrowerPhone,
    this.borrowerPlace,
    this.brokerId,
    required this.principalAmount,
    this.interestRatePercent,
    this.startDate,
    this.monthlyInterest,
    this.loanType = 'solo',
    this.notes,
    this.status = 'active',
  });

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'borrower_name': borrowerName,
      'borrower_phone': borrowerPhone,
      'borrower_place': borrowerPlace,
      'broker_id': brokerId,
      'principal_amount': principalAmount,
      'interest_rate_percent': interestRatePercent,
      'start_date': startDate,
      'monthly_interest': monthlyInterest,
      'loan_type': loanType,
      'notes': notes,
      'status': status,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory Loan.fromMap(Map<String, dynamic> map) {
    return Loan(
      id: map['id'],
      borrowerName: map['borrower_name'],
      borrowerPhone: map['borrower_phone'],
      borrowerPlace: map['borrower_place'],
      brokerId: map['broker_id'],
      principalAmount: map['principal_amount']?.toDouble() ?? 0.0,
      interestRatePercent: map['interest_rate_percent']?.toDouble(),
      startDate: map['start_date'],
      monthlyInterest: map['monthly_interest']?.toDouble(),
      loanType: map['loan_type'],
      notes: map['notes'],
      status: map['status'],
    );
  }
}
