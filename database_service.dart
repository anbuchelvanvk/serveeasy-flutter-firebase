import 'package:firebase_database/firebase_database.dart';
import 'models/outage_report.dart';
import 'models/technician.dart';

class DatabaseService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // Fetch customer by phone for login/verification
  Future<Map<dynamic, dynamic>?> getCustomer(String phone) async {
    final snapshot = await _dbRef
        .child("customers")
        .orderByChild("phone")
        .equalTo(phone)
        .get();
    if (snapshot.exists) return (snapshot.value as Map).values.first;
    return null;
  }

  // Create new customer entry
  Future<void> createCustomer(
    String phone,
    String name,
    String pincode,
    String address,
  ) async {
    await _dbRef.child("customers").child(phone).set({
      "name": name,
      "phone": phone,
      "pincode": pincode,
      "address": address,
    });
  }

  // Secure technician login logic
  Future<Technician?> loginTechnician(String techId, String password) async {
    final snapshot = await _dbRef.child("technicians").child(techId).get();
    if (snapshot.exists) {
      final data = snapshot.value as Map;
      if (data['password'] == password) return Technician.fromMap(techId, data);
    }
    return null;
  }

  Future<List<OutageReport>> getAllOutages() async {
    final snapshot = await _dbRef.child("outages").get();
    if (!snapshot.exists) return [];
    Map<dynamic, dynamic> values = snapshot.value as Map<dynamic, dynamic>;
    return values.entries
        .map((e) => OutageReport.fromMap(e.key, e.value))
        .toList();
  }

  Future<bool> loginAdmin(String adminId, String password) async {
    final snapshot = await _dbRef.child("admins").child(adminId).get();
    if (snapshot.exists) {
      final data = snapshot.value as Map;
      return data['password'] == password;
    }
    return false;
  }

  // Specialty filtering for technicians (checks the 'specialties' list in DB)
  Future<List<Technician>> getTechniciansBySpecialty(
    String requestedService,
  ) async {
    try {
      final snapshot = await _dbRef.child("technicians").get();
      if (snapshot.exists) {
        Map<dynamic, dynamic> data = snapshot.value as Map;
        return data.entries
            .map((e) => Technician.fromMap(e.key, e.value as Map))
            .where(
              (tech) => tech.specialties.any(
                (s) =>
                    s.toLowerCase().trim() ==
                    requestedService.toLowerCase().trim(),
              ),
            )
            .toList();
      }
    } catch (e) {
      print("Error: $e");
    }
    return [];
  }

  // Get already booked slots to prevent double-booking
  Future<List<String>> getBookedSlots(String techId) async {
    final snapshot = await _dbRef
        .child("outages")
        .orderByChild("technicianId")
        .equalTo(techId)
        .get();
    if (!snapshot.exists) return [];
    Map<dynamic, dynamic> data = snapshot.value as Map;
    return data.values.map((e) => e['preferredSlot'].toString()).toList();
  }

  // UPDATED: Fetches customer history using the fromMap factory logic
  Future<List<OutageReport>> getCustomerHistory(String phone) async {
    try {
      final snapshot = await _dbRef
          .child("outages")
          .orderByChild("userId")
          .equalTo(phone)
          .get();
      if (snapshot.exists) {
        Map<dynamic, dynamic> values = snapshot.value as Map<dynamic, dynamic>;

        // Correctly mapping using entries to pass the unique Firebase key
        List<OutageReport> history = values.entries.map((e) {
          return OutageReport.fromMap(e.key, e.value as Map<dynamic, dynamic>);
        }).toList();

        // Sort by newest first
        history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return history;
      }
    } catch (e) {
      print("History Error: $e");
    }
    return [];
  }

  // Update status (Pending -> Completed) used by TechnicianView
  Future<void> updateReportStatus(String reportKey, String newStatus) async {
    await _dbRef.child("outages").child(reportKey).update({
      'status': newStatus,
    });
  }

  // Fetch technician schedule for the portal view
  Future<List<Map<String, dynamic>>> getTechnicianSchedule(
    String techId,
  ) async {
    final snapshot = await _dbRef
        .child("outages")
        .orderByChild("technicianId")
        .equalTo(techId)
        .get();
    if (snapshot.exists) {
      Map<dynamic, dynamic> values = snapshot.value as Map<dynamic, dynamic>;
      return values.entries
          .map((e) => {"key": e.key, ...Map<String, dynamic>.from(e.value)})
          .toList();
    }
    return [];
  }

  // Finalize booking entry in the database
  Future<void> reportOutage(OutageReport report) async {
    await _dbRef.child("outages").push().set(report.toJson());
  }

  // 1. Delete a specific ticket
  Future<void> deleteOutage(String key) async {
    await _dbRef.child("outages").child(key).remove();
  }

  // 2. Fetch all technicians for the re-assignment list
  Future<List<Technician>> getAllTechnicians() async {
    final snapshot = await _dbRef.child("technicians").get();
    if (!snapshot.exists) return [];
    Map data = snapshot.value as Map;
    return data.entries
        .map((e) => Technician.fromMap(e.key, e.value as Map))
        .toList();
  }

  // 3. Update the technician assigned to a ticket
  Future<void> updateTechnician(String reportKey, String techId) async {
    await _dbRef.child("outages").child(reportKey).update({
      'technicianId': techId,
    });
  }

  Future<void> submitRating(String reportKey, double rating) async {
    await _dbRef.child("outages").child(reportKey).update({'rating': rating});
  }

  Stream<DatabaseEvent> getSupportChatStream(String userId) {
    return _dbRef.child("admin_support_chats").child(userId).onValue;
  }

  Stream<DatabaseEvent> getAllSupportChats() {
    return _dbRef.child("admin_support_chats").onValue;
  }

  // ✅ Client side: Send message to Admin
  Future<void> sendAdminReply(String userId, String text) async {
    await _dbRef.child("admin_support_chats").child(userId).push().set({
      'text': text,
      'sender': 'admin',
      'timestamp': DateTime.now().millisecondsSinceEpoch, // Use int
    });
  }

  // ✅ New: Client side sends message as integer
  Future<void> sendUserSupportMessage(String phone, String text) async {
    await _dbRef.child("admin_support_chats").child(phone).push().set({
      'text': text,
      'sender': 'user',
      'timestamp': DateTime.now().millisecondsSinceEpoch, // Use int
    });
  }
  Future<void> updateAdminLastRead(String userId) async {
  await _dbRef.child("admin_support_chats").child(userId).update({
    'admin_last_read': DateTime.now().millisecondsSinceEpoch,
  });
}
Future<void> updateUserLastRead(String phone) async {
  await _dbRef.child("admin_support_chats").child(phone).update({
    'user_last_read': DateTime.now().millisecondsSinceEpoch,
  });
}
}
