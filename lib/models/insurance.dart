class Insurance {
  int? id;
  String customerName;
  double amountPaid;
  String datePaid;
  String? paidTo;
  double? refundAmount;
  String? refundDate;
  String? refundMethod;
  String? notes;

  Insurance({
    this.id,
    required this.customerName,
    required this.amountPaid,
    required this.datePaid,
    this.paidTo,
    this.refundAmount,
    this.refundDate,
    this.refundMethod,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'customer_name': customerName,
      'amount_paid': amountPaid,
      'date_paid': datePaid,
      'paid_to': paidTo,
      'refund_amount': refundAmount,
      'refund_date': refundDate,
      'refund_method': refundMethod,
      'notes': notes,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory Insurance.fromMap(Map<String, dynamic> map) {
    return Insurance(
      id: map['id'],
      customerName: map['customer_name'],
      amountPaid: map['amount_paid']?.toDouble() ?? 0.0,
      datePaid: map['date_paid'],
      paidTo: map['paid_to'],
      refundAmount: map['refund_amount']?.toDouble(),
      refundDate: map['refund_date'],
      refundMethod: map['refund_method'],
      notes: map['notes'],
    );
  }
}
