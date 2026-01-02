class Technician {
  final String id;
  final String name;
  final List<String> specialties;
  final List<String> availableSlots;
  final String password; // Added for secure login

  Technician({
    required this.id,
    required this.name,
    required this.specialties,
    required this.availableSlots,
    required this.password,
  });

  factory Technician.fromMap(String id, Map<dynamic, dynamic> map) {
    return Technician(
      id: id,
      name: map['name'] ?? '',
      specialties: List<String>.from(map['specialties'] ?? []),
      availableSlots: List<String>.from(map['availableSlots'] ?? []),
      password: map['password'] ?? '',
    );
  }
}