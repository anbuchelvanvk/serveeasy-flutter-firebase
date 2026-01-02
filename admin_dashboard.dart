import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ Required for SystemUiOverlayStyle
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'database_service.dart';
import 'models/outage_report.dart';
import 'models/technician.dart';
import 'package:serveeasy_app/main.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'admin_support_view.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final DatabaseService _db = DatabaseService();
  String _searchQuery = "";

  String _selectedTimeFrame = "One Month";

  List<OutageReport> _filterByTime(List<OutageReport> reports) {
    final now = DateTime.now();
    return reports.where((report) {
      final difference = now.difference(report.timestamp).inDays;
      if (_selectedTimeFrame == "One Day") return difference < 1;
      if (_selectedTimeFrame == "One Week") return difference < 7;
      return difference < 30; // Default: One Month
    }).toList();
  }

  Color _getStatusColor(String status) {
    if (status == "Completed") return const Color(0xFF2E7D32);
    if (status == "Overdue") return const Color(0xFFD32F2F);
    return const Color(0xFFE65100);
  }

  // ✅ CSV Export Logic
  Future<void> _exportToCSV(List<OutageReport> reports) async {
    List<List<dynamic>> rows = [];
    rows.add([
      "User Phone",
      "Service Type",
      "Status",
      "Issue",
      "Address",
      "Date",
    ]);
    for (var r in reports) {
      rows.add([
        r.userId,
        r.outageType,
        r.status,
        r.description,
        r.address,
        r.timestamp.toString().substring(0, 10),
      ]);
    }
    String csvData = const ListToCsvConverter().convert(rows);
    await Share.shareXFiles([
      XFile.fromData(
        Uint8List.fromList(csvData.codeUnits),
        name: 'ServeEasy_Admin_Report.csv',
        mimeType: 'text/csv',
      ),
    ], subject: 'ServeEasy Service Export');
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryTextColor = isDark ? Colors.white : Colors.black;
    final Color secondaryTextColor = isDark ? Colors.white70 : Colors.black87;
    final Color cardBackground = isDark
        ? const Color(0xFF1E1E1E)
        : Colors.white;
    final Color scaffoldBg = isDark
        ? const Color(0xFF121212)
        : const Color(0xFFF1F4F9);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        toolbarHeight: 80,
        elevation: 2,
        centerTitle: true,
        backgroundColor: const Color(0xFF0061FF),

        // ✅ 1. Fix Status Bar Visibility (Clock/Battery)
        systemOverlayStyle: SystemUiOverlayStyle.light,

        // ✅ 2. Make Toggle Menu Logo (Hamburger) White
        iconTheme: const IconThemeData(color: Colors.white),

        // ✅ 3. Add White Back Button near Logo
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),

        title: Text(
          "Admin Analytics",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white, // ✅ Keep Title White
            fontSize: 20,
          ),
        ),
        actions: [
          // ✅ NEW: Time Filter Dropdown
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: "Refresh Tickets",
            onPressed: () {
              setState(() {}); // Triggers FutureBuilder to re-fetch tickets
            },
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedTimeFrame,
              dropdownColor: const Color(0xFF0061FF),
              icon: const Icon(Icons.filter_list, color: Colors.white),
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              onChanged: (String? newValue) {
                if (newValue != null)
                  setState(() => _selectedTimeFrame = newValue);
              },
              items: ["One Day", "One Week", "One Month"]
                  .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  })
                  .toList(),
            ),
          ),
          _buildHeaderAction(
            icon: Icons.chat_bubble_outline,
            label: "Support",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (c) => const AdminSupportView()),
            ),
          ),
          FutureBuilder<List<OutageReport>>(
            future: _db.getAllOutages(),
            builder: (context, snapshot) => _buildHeaderAction(
              icon: Icons.file_download,
              label: "Export",
              onTap: () => snapshot.hasData
                  ? _exportToCSV(_filterByTime(snapshot.data!))
                  : null,
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),

      body: FutureBuilder<List<OutageReport>>(
        future: _db.getAllOutages(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.isEmpty)
            return Center(
              child: Text(
                "No tickets found.",
                style: TextStyle(color: primaryTextColor),
              ),
            );

          var data = _filterByTime(snapshot.data!);

          Map<String, double> counts = {"ELECTRICITY": 0, "WATER": 0, "GAS": 0};
          int completed = 0;
          int pending = 0;

          for (var r in data) {
            String type = r.outageType.toUpperCase().trim();
            if (counts.containsKey(type)) {
              counts[type] = counts[type]! + 1;
            }

            if (counts.containsKey(type)) {
              counts[type] = counts[type]! + 1;
              }

            if (r.status == "Completed")
              completed++;
            else
              pending++;
          }
          double chartMaxY =
              (counts.values.isEmpty
                      ? 5
                      : counts.values.reduce((a, b) => a > b ? a : b) + 2)
                  .toDouble();

          final filteredData = data
              .where(
                (report) =>
                    report.userId.contains(_searchQuery) ||
                    report.outageType.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ),
              )
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Service Demand (${_selectedTimeFrame})",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 20),

                // --- BAR CHART ---
                Container(
                  height: 250,
                  padding: const EdgeInsets.fromLTRB(10, 24, 16, 16),
                  decoration: BoxDecoration(
                    color: cardBackground,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: chartMaxY,
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, m) {
                              final style = TextStyle(
                                color: primaryTextColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              );
                              if (v == 0) return Text('Elec', style: style);
                              if (v == 1) return Text('Water', style: style);
                              if (v == 2) return Text('Gas', style: style);
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (v, m) => v == v.toInt()
                                ? Text(
                                    v.toInt().toString(),
                                    style: TextStyle(
                                      color: primaryTextColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : const SizedBox(),
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: isDark ? Colors.white10 : Colors.black12,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: [
                        _makeGroup(0, counts["ELECTRICITY"]!, Colors.blue),
                        _makeGroup(1, counts["WATER"]!, Colors.cyan),
                        _makeGroup(2, counts["GAS"]!, Colors.orange),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        "Revenue",
                        "₹${completed * 500}", // ✅ Use 'completed' count instead of 'data.length'
                        Icons.payments,
                        const Color(0xFF43A047),
                        isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        "Completed",
                        "$completed",
                        Icons.check_circle,
                        const Color(0xFF2E7D32),
                        isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        "Pending",
                        "$pending",
                        Icons.pending_actions,
                        const Color(0xFFE65100),
                        isDark,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),
                Text(
                  "Activity Log",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 15),

                // ✅ Search Bar Styling
                TextField(
                  style: TextStyle(color: primaryTextColor),
                  decoration: InputDecoration(
                    hintText: "Search phone or service...",
                    hintStyle: TextStyle(
                      color: secondaryTextColor.withOpacity(0.5),
                    ),
                    prefixIcon: Icon(Icons.search, color: secondaryTextColor),
                    filled: true,
                    fillColor: cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
                const SizedBox(height: 15),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredData.length,
                  itemBuilder: (c, i) {
                    final report = filteredData[i];
                    return Card(
                      color: cardBackground,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white10
                              : Colors.black.withOpacity(0.05),
                        ),
                      ),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(
                          "${report.outageType.toUpperCase()} - ${report.userId}",
                          style: GoogleFonts.poppins(
                            color: primaryTextColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          "Status: ${report.status} (${report.timestamp.toString().substring(0, 10)})",
                          style: GoogleFonts.poppins(
                            color: secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: _getStatusColor(report.status),
                        ),
                        onTap: () => _showTicketDetails(context, report),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- (Helper methods remain the same) ---

  void _showTicketDetails(BuildContext context, OutageReport report) {
    final bool isCompleted = report.status.toLowerCase() == "completed";
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "TICKET MANAGEMENT",
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDetailItem("USER PHONE", report.userId, isDark),
            _buildDetailItem("ADDRESS", report.address, isDark),
            _buildDetailItem("ISSUE", report.description, isDark),
            const Divider(),
            if (!isCompleted)
              ElevatedButton.icon(
                onPressed: () => _showSmartReassign(context, report),
                icon: const Icon(Icons.engineering),
                label: const Text("RE-ASSIGN TECH"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0061FF),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 45),
                ),
              ),
            if (isCompleted)
              ElevatedButton.icon(
                onPressed: () => _generateAdminPdf(report),
                icon: const Icon(Icons.download),
                label: const Text("DOWNLOAD RECEIPT"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 45),
                ),
              ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => _showDeleteConfirmation(context, report),
              icon: const Icon(Icons.delete),
              label: const Text("DELETE TICKET"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSmartReassign(BuildContext context, OutageReport report) async {
    List<Technician> allTechs = await _db.getAllTechnicians();
    List<Technician> qualifiedTechs = allTechs
        .where(
          (t) => t.specialties.any(
            (s) =>
                s.toLowerCase().trim() ==
                report.outageType.toLowerCase().trim(),
          ),
        )
        .toList();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "QUALIFIED TECHNICIANS",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Divider(),
            Expanded(
              child: qualifiedTechs.isEmpty
                  ? const Center(child: Text("No qualified technicians found."))
                  : ListView.builder(
                      itemCount: qualifiedTechs.length,
                      itemBuilder: (context, index) => ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(
                          qualifiedTechs[index].name,
                          style: GoogleFonts.poppins(),
                        ),
                        onTap: () async {
                          await _db.updateTechnician(
                            report.key!,
                            qualifiedTechs[index].id,
                          );
                          Navigator.pop(c);
                          Navigator.pop(context);
                          setState(() {});
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, OutageReport report) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          "Confirm Deletion",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text("Permanently delete ticket for ${report.userId}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _db.deleteOutage(report.key!);
              Navigator.pop(c);
              Navigator.pop(context);
              setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
            ),
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _generateAdminPdf(OutageReport report) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          children: [
            pw.Center(
              child: pw.Text(
                "SERVEEASY RECEIPT",
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text("User: ${report.userId}"),
            pw.Text("Service: ${report.outageType.toUpperCase()}"),
            pw.Text("Address: ${report.address}"),
            pw.Text("Issue: ${report.description}"),
            pw.Text("Rating: ${report.rating ?? 'N/A'}"),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  BarChartGroupData _makeGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 28,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white60 : Colors.black54,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white60 : Colors.black54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
