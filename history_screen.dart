import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'database_service.dart';
import 'models/outage_report.dart';

class HistoryScreen extends StatelessWidget {
  final String phone;
  final DatabaseService _db = DatabaseService();

  HistoryScreen({super.key, required this.phone});

  // ✅ 1. Helper to get status-specific colors
  Color _getStatusColor(String status) {
    if (status == "Completed") return Colors.green.shade700;
    if (status == "Cancelled") return Colors.red.shade700;
    return Colors.orange.shade700;
  }

  // ✅ 2. Defined the missing _showStatusDetails method
  void _showStatusDetails(BuildContext context, OutageReport report) {
    bool isCompleted = report.status == "Completed";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "${report.outageType.toUpperCase()} STATUS 🔍",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow("Current Status", report.status, _getStatusColor(report.status)),
            _buildDetailRow("Description", report.description, Colors.black87),
            _buildDetailRow("Time Slot", report.preferredSlot ?? "ASAP", Colors.blueGrey),
            const Divider(height: 30),
            if (isCompleted)
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 50),
                    SizedBox(height: 8),
                    Text("Job Finished Successfully!",
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            else
              const Center(
                child: Text("👷 Our technician will reach you shortly.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontStyle: FontStyle.italic)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color valColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.poppins(color: Colors.black, fontSize: 14),
          children: [
            TextSpan(text: "$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value, style: TextStyle(color: valColor, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("History: $phone", 
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0061FF),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: FutureBuilder<List<OutageReport>>(
        future: _db.getCustomerHistory(phone),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No report history found. 📭"));
          }

          // ✅ 3. Extracting history from snapshot to fix the 'history' error
          final List<OutageReport> history = snapshot.data!;

          return ListView.builder(
            itemCount: history.length,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemBuilder: (context, index) {
              final report = history[index];
              bool isCompleted = report.status == 'Completed';

              return Card(
                elevation: 3,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                // ✅ 4. Green tone for Completed jobs
                color: isCompleted ? const Color(0xFFE8F5E9) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(
                    color: isCompleted ? Colors.green.shade300 : Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                child: ListTile(
                  onTap: () => _showStatusDetails(context, report),
                  leading: CircleAvatar(
                    backgroundColor: isCompleted ? Colors.green : Colors.orange,
                    child: Icon(
                      isCompleted ? Icons.check : Icons.access_time,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    "${report.outageType.toUpperCase()} SERVICE",
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text("Status: ${report.status}", 
                    style: GoogleFonts.poppins(color: _getStatusColor(report.status), fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                ),
              );
            },
          );
        },
      ),
    );
  }
}