class OutageReport {
  final String? key; // Unique Firebase key
  final String userId;
  final String outageType;
  final String description;
  final String address;
  final DateTime timestamp;
  final String? technicianId;
  final String? preferredSlot;
  final String status;
  final String? completionPin;
  final double? rating; // NEW FIELD

  OutageReport({
    this.key,
    required this.userId,
    required this.outageType,
    required this.description,
    required this.address,
    required this.timestamp,
    this.technicianId,
    this.preferredSlot,
    this.status = 'Pending',
    this.completionPin,
    this.rating, // ADD TO CONSTRUCTOR
  });

  // Convert Firebase data to OutageReport object
  factory OutageReport.fromMap(String key, Map<dynamic, dynamic> map) {
    return OutageReport(
      key: key,
      userId: map['userId'] ?? '',
      outageType: map['outageType'] ?? 'General',
      description: map['description'] ?? '',
      address: map['address'] ?? '',
      technicianId: map['technicianId'],
      preferredSlot: map['preferredSlot'],
      status: map['status'] ?? 'Pending',
      completionPin: map['completionPin']?.toString(), // MAP PIN FROM DB
      timestamp: DateTime.parse(map['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  // Convert object to JSON for Firebase
  Map<String, dynamic> toJson() {
    return {
      "userId": userId,
      "outageType": outageType,
      "description": description,
      "address": address,
      "timestamp": timestamp.toIso8601String(),
      "technicianId": technicianId,
      "preferredSlot": preferredSlot,
      "status": status,
      "completionPin": completionPin,
      'rating': rating, // INCLUDE PIN IN JSON
    };
  }
}