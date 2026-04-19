class Payment {
  int? id;
  int loanId;
  String date;
  double amount;
  String paymentType;
  String method;
  String? notes;

  Payment({
    this.id,
    required this.loanId,
    required this.date,
    required this.amount,
    required this.paymentType,
    required this.method,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'loan_id': loanId,
      'date': date,
      'amount': amount,
      'payment_type': paymentType,
      'method': method,
      'notes': notes,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'],
      loanId: map['loan_id'],
      date: map['date'],
      amount: map['amount']?.toDouble() ?? 0.0,
      paymentType: map['payment_type'],
      method: map['method'],
      notes: map['notes'],
    );
  }
}
