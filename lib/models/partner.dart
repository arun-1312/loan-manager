class Partner {
  int? id;
  String name;
  String? phone;
  double? sharePercent;

  Partner({this.id, required this.name, this.phone, this.sharePercent});

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'name': name,
      'phone': phone,
      'share_percent': sharePercent,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory Partner.fromMap(Map<String, dynamic> map) {
    return Partner(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
      sharePercent: map['share_percent']?.toDouble(),
    );
  }
}
