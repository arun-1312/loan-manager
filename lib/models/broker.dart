class Broker {
  int? id;
  String name;
  String? phone;

  Broker({this.id, required this.name, this.phone});

  // Convert model → Map (for DB insert)
  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'name': name,
      'phone': phone,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  // Convert DB Map → model
  factory Broker.fromMap(Map<String, dynamic> map) {
    return Broker(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
    );
  }
}
