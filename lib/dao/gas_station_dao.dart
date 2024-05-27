class GasStationDao {
  int id;
  String location;
  double price;

  GasStationDao({required this.id, required this.location, required this.price});

  factory GasStationDao.fromJson(Map<String, dynamic> json) {
    return GasStationDao(
        id: json['id'],
        location: '${json["adresse"]}, ${json["ville"]}',
        price: json['gazole_prix']);
  }
}
