import 'package:flutter/material.dart';
import 'database_service.dart';

class TechnicianView extends StatefulWidget {
  final String techId, techName;
  const TechnicianView({super.key, required this.techId, required this.techName});

  @override
  State<TechnicianView> createState() => _TechnicianViewState();
}

class _TechnicianViewState extends State<TechnicianView> {
  final DatabaseService _db = DatabaseService();

  Color _getStatusColor(String status) {
    if (status == "Completed") return Colors.green;
    if (status == "Overdue") return Colors.red;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Schedule: ${widget.techName}"),
        backgroundColor: const Color(0xFF0061FF),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _db.getTechnicianSchedule(widget.techId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.isEmpty) return const Center(child: Text("No tasks assigned yet."));

          return ListView.builder(
            itemCount: snapshot.data!.length,
            padding: const EdgeInsets.all(10),
            itemBuilder: (context, index) {
              var job = snapshot.data![index];
              String status = job['status'] ?? 'Pending';
              
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                color: _getStatusColor(status).withOpacity(0.05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(
                    "SLOT: ${job['preferredSlot']}".toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      "ADDRESS: ${job['address']}\nISSUE: ${job['description']}\nSTATUS: ${status.toUpperCase()}",
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                  trailing: Icon(Icons.verified_user, color: _getStatusColor(status)),
                  onTap: status == "Completed" ? null : () => _showCompletionDialog(job),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // UPDATED: Dialog that handles PIN verification
  void _showCompletionDialog(Map<String, dynamic> job) {
    final TextEditingController pinController = TextEditingController();
    final String correctPin = job['completionPin']?.toString() ?? "";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Complete Service"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Please ask the customer for their 4-digit Verification PIN to close this request."),
            const SizedBox(height: 20),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Enter 4-Digit PIN",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              if (pinController.text == correctPin) {
                await _db.updateReportStatus(job['key'], "Completed");
                Navigator.pop(context);
                setState(() {}); // Refresh the list
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("✅ Job successfully verified and completed!")),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("⚠️ Incorrect PIN. Please check with the customer."),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("Verify & Complete"),
          ),
        ],
      ),
    );
  }
}