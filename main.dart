import 'dart:async';
import 'dart:math' as math;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:serveeasy_app/admin_dashboard.dart';
import 'firebase_options.dart';
import 'database_service.dart';
import 'models/outage_report.dart';
import 'models/message.dart';
import 'models/technician.dart';
import 'history_screen.dart';
import 'technician_view.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

enum ChatState {
  askingPhone,
  decidingService,
  registeringName,
  verifyingPincode,
  addressMismatch,
  askingAddress,
  selectingType,
  describing,
  selectingTech,
  selectingSlot,
  completed,
  restarting,
  supportChat,
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Add a small timeout so it doesn't hang forever if the internet is bad
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform.copyWith(
        databaseURL: "https://serveeasy-app-default-rtdb.firebaseio.com/",
      ),
    ).timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint("Firebase failed to initialize: $e");
  }

  runApp(const ServeEasyApp());
}

class ServeEasyApp extends StatefulWidget {
  const ServeEasyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ServeEasy',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SplashScreen(),
    );
  }

  static _ServeEasyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_ServeEasyAppState>();

  @override
  State<ServeEasyApp> createState() => _ServeEasyAppState();
}

class _ServeEasyAppState extends State<ServeEasyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF0061FF),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF0061FF),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      ),
      home: const ChatScreen(),
    );
  }
}

class FluentLoader extends StatefulWidget {
  const FluentLoader({super.key});
  @override
  State<FluentLoader> createState() => _FluentLoaderState();
}

class _FluentLoaderState extends State<FluentLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Stack(
        children: List.generate(
          5,
          (index) => Transform.rotate(
            angle: (index * 0.25) * math.pi,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 4), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ChatScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0061FF), Color(0xFF60EFFF)],
            begin: Alignment.topCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset("assets/logo.png", height: 120),
            const SizedBox(height: 50),
            const SizedBox(width: 50, height: 50, child: FluentLoader()),
            const SizedBox(height: 30),
            Text(
              "ServeEasy",
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

DateTime _parseDateTime(dynamic timestamp) {
  if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
  if (timestamp is String)
    return DateTime.tryParse(timestamp) ?? DateTime.now();
  return DateTime.now();
}

class _ChatScreenState extends State<ChatScreen> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _showServiceChips = false;
  bool _showServiceDecisionButtons = false;
  bool _showRestartButtons = false;
  bool _showExitButton = false;

  final List<Message> _messages = [
    Message(
      text:
          "👋 Good morning! Welcome to ServeEasy Support. Please enter your 10-digit mobile number.",
      type: MessageType.agent,
      timestamp: DateTime.now(),
    ),
  ];

  ChatState _state = ChatState.askingPhone;

  String? _phone,
      _name,
      _address,
      _type,
      _desc,
      _pincode,
      _tempPincode,
      _currentBookingId,
      _currentPin;

  List<Technician> _techOptions = [];
  List<String> _slots = [];
  Technician? _selectedTech;

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "Exit ServeEasy?",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: const Text("Are you sure you want to close the application?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c), // Just closes the dialog
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () => SystemNavigator.pop(), // Closes the app
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("EXIT", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addMsg(String text, MessageType type, {bool isConfirmation = false}) {
    setState(
      () => _messages.add(
        Message(
          text: text,
          type: type,
          timestamp: DateTime.now(),
          isConfirmation: isConfirmation,
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  bool _isValidPincode(String input) =>
      input.length == 6 && int.tryParse(input) != null;

  bool _isValidPhone(String input) => RegExp(r'^[6-9]\d{9}$').hasMatch(input);

  String _generateBookingId() => "SE-${Random().nextInt(9000) + 1000}";

  String _generatePin() => (Random().nextInt(9000) + 1000).toString();

  void _handleSend() async {
    String input = _controller.text.trim();
    if (input.isEmpty) return;

    if (_state == ChatState.supportChat) {
      if (_phone != null) {
        await _db.sendUserSupportMessage(_phone!, input);
        await _db.updateUserLastRead(
          _phone!,
        ); // ✅ Mark messages as read when user replies
        _controller.clear();
      }
      return;
    }

    _addMsg(input, MessageType.user);
    _controller.clear();

    try {
      switch (_state) {
        case ChatState.askingPhone:
          if (!_isValidPhone(input)) {
            _addMsg(
              "⚠️ Please enter a valid 10-digit mobile number.",
              MessageType.agent,
            );
            return;
          }

          _phone = input;
          _addMsg("Checking records... ⏳", MessageType.agent);
          var user = await _db.getCustomer(input);
          setState(() => _messages.removeLast());

          if (user != null) {
            _name = user['name'];
            _address = user['address'];
            _pincode = user['pincode']?.toString();

            List<OutageReport> history = await _db.getCustomerHistory(input);
            List<OutageReport> active = history
                .where(
                  (r) => r.status != 'Completed' && r.status != 'Cancelled',
                )
                .toList();

            if (active.isNotEmpty) {
              _addMsg(
                "Welcome back, $_name! You have active bookings. Do you need an **Update** or a **New** booking?",
                MessageType.agent,
              );
              setState(() {
                _state = ChatState.decidingService;
                _showServiceDecisionButtons = true;
              });
            } else {
              _addMsg(
                "Welcome back, $_name! 🏠 Please provide your area Pincode to start.",
                MessageType.agent,
              );
              _state = ChatState.verifyingPincode;
            }
          } else {
            _addMsg(
              "Welcome! 👤 Please provide your full name to register.",
              MessageType.agent,
            );
            _state = ChatState.registeringName;
          }
          break;

        case ChatState.decidingService:
          if (input.toLowerCase().contains("update")) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (c) => HistoryScreen(phone: _phone!)),
            );
          } else {
            _addMsg(
              "🏠 Please provide area Pincode to start new request.",
              MessageType.agent,
            );
            _state = ChatState.verifyingPincode;
          }
          break;

        case ChatState.registeringName:
          _name = input;
          _addMsg(
            "Thank you, $_name. 📍 Please enter your current service address.",
            MessageType.agent,
          );
          _state = ChatState.askingAddress;
          break;

        case ChatState.askingAddress:
          _address = input;
          _addMsg(
            "Address saved. Now, please enter the 6-digit Pincode for this area.",
            MessageType.agent,
          );
          _state = ChatState.verifyingPincode;
          break;

        case ChatState.verifyingPincode:
          if (!_isValidPincode(input)) {
            _addMsg("⚠️ Invalid Pincode.", MessageType.agent);
            return;
          }

          // Detect Mismatch for Existing Users
          if (_pincode != null && _pincode != input) {
            // Generate the hint (e.g., 606604 becomes 60****)
            String hint = _pincode!.length >= 2
                ? "${_pincode!.substring(0, 2)}****"
                : "****";

            _addMsg(
              "It seems you have changed your address. \n\n✅ If **YES**, please enter your **new address**. \n❌ If **NO**, please enter the **old pincode** starting with ($hint).",
              MessageType.agent,
            );

            setState(() {
              _tempPincode = input; // Store the new pincode temporarily
              _state = ChatState.addressMismatch;
            });
            return;
          }
          _pincode = input;
          _proceedToServiceSelection();
          break;
        case ChatState.selectingType:
          _type = input;
          setState(() => _showServiceChips = false);
          _addMsg("Briefly describe the issue. 📝", MessageType.agent);
          _state = ChatState.describing;
          break;

        case ChatState.describing:
          _desc = input;
          _addMsg("Searching technicians... 🔍", MessageType.agent);
          final found = await _db.getTechniciansBySpecialty(_type!);
          setState(() {
            _techOptions = found;
            if (_techOptions.isNotEmpty) {
              String list = "";
              for (int i = 0; i < _techOptions.length; i++)
                list += "${i + 1}. ${_techOptions[i].name}\n";
              _addMsg(
                "Select technician (Type the Number):\n$list",
                MessageType.agent,
              );
              _state = ChatState.selectingTech;
            } else {
              _addMsg(
                "No specialized technicians available for $_type.",
                MessageType.agent,
              );
              _finish(null, null, "ASAP");
            }
          });
          break;

        case ChatState.addressMismatch:
          // 1. If user enters the OLD pincode (Correcting their mistake)
          if (input == _pincode) {
            _addMsg("Pincode verified. ✅", MessageType.agent);
            _proceedToServiceSelection();
          }
          // 2. If user enters a 6-digit number that ISN'T the old pincode
          else if (_isValidPincode(input)) {
            _addMsg(
              "⚠️ That doesn't match our records. If you moved, please type your new address. Otherwise, enter the old pincode.",
              MessageType.agent,
            );
          }
          // 3. If user types their NEW address
          else {
            setState(() {
              _address = input; // Update to the new address
              _pincode = _tempPincode; // Update to the new pincode
            });

            // Update the database with new address/pincode
            await _db.createCustomer(_phone!, _name!, _pincode!, _address!);

            _addMsg("Address updated successfully! 📍", MessageType.agent);
            _proceedToServiceSelection();
          }
          break;

        case ChatState.selectingTech:
          int? idx = int.tryParse(input);
          if (idx != null && idx > 0 && idx <= _techOptions.length) {
            _selectedTech = _techOptions[idx - 1];
            List<String> booked = await _db.getBookedSlots(_selectedTech!.id);
            List<String> open = _selectedTech!.availableSlots
                .where((s) => !booked.contains(s))
                .toList();
            setState(() {
              _slots = open;
              if (_slots.isEmpty) {
                _addMsg(
                  "Sorry, ${_selectedTech!.name} is booked.",
                  MessageType.agent,
                );
                _state = ChatState.describing;
              } else {
                String sList = "";
                for (int i = 0; i < _slots.length; i++)
                  sList += "${i + 1}. ${_slots[i]}\n";
                _addMsg(
                  "Available slots for ${_selectedTech!.name}:\n$sList",
                  MessageType.agent,
                );
                _state = ChatState.selectingSlot;
              }
            });
          }
          break;

        case ChatState.selectingSlot:
          int? sIdx = int.tryParse(input);
          if (sIdx != null && sIdx > 0 && sIdx <= _slots.length) {
            _finish(_selectedTech!.id, _selectedTech!.name, _slots[sIdx - 1]);
          }
          break;

        default:
          break;
      }
    } catch (e) {
      print("Database Error: $e");
      _addMsg(
        "❌ Connection error. Please check your internet or Firebase rules.",
        MessageType.agent,
      );
    }
  }

  void _finish(String? tId, String? tName, String slot) async {
    _currentBookingId = _generateBookingId();
    _currentPin = _generatePin();
    await _db.reportOutage(
      OutageReport(
        userId: _phone!,
        outageType: _type!,
        description: _desc!,
        address: "$_address (Pin: $_pincode)",
        timestamp: DateTime.now(),
        technicianId: tId,
        preferredSlot: slot,
        status: 'Pending',
        completionPin: _currentPin,
      ),
    );

    _addMsg(
      "✅ Booking Confirmed! **${tName ?? "A technician"}** will visit during the **$slot** slot. \n\n🔑 PIN: **$_currentPin**",
      MessageType.agent,
      isConfirmation: true,
    );

    Future.delayed(const Duration(seconds: 2), () {
      _addMsg(
        "Would you like to request any other service today?",
        MessageType.agent,
      );
      setState(() {
        _state = ChatState.restarting;
        _showRestartButtons = true;
      });
    });
  }

  void _proceedToServiceSelection() {
    _addMsg(
      "Verification successful! ✅ Which service requires attention?",
      MessageType.agent,
    );
    setState(() {
      _showServiceChips = true;
      _state = ChatState.selectingType;
    });
  }

  // --- DRAWER & UI HELPERS ---

  // lib/main.dart - Inside _buildCustomerDrawer

  // lib/main.dart - Inside _buildCustomerDrawer method

  Widget _buildCustomerDrawer(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0061FF), Color(0xFF60EFFF)],
              ),
            ),
            accountName: Text(_name ?? "Welcome!"),
            accountEmail: Text(_phone ?? "Guest User"),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: AssetImage("assets/logo.png"),
              child: Icon(Icons.person, color: Color(0xFF0061FF)),
            ),
          ),

          // --- Navigation Options ---
          ListTile(
            leading: const Icon(Icons.history, color: Colors.blue),
            title: Text("Full Job History", style: GoogleFonts.poppins()),
            onTap: () {
              Navigator.pop(context);
              if (_phone != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) => HistoryScreen(phone: _phone!),
                  ),
                );
              } else {
                _showLoginRequiredPopup("view history");
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long, color: Colors.blue),
            title: Text("Download Bills", style: GoogleFonts.poppins()),
            onTap: () {
              Navigator.pop(context);
              if (_phone != null) {
                _showBillHistorySheet(context);
              } else {
                _showLoginRequiredPopup("access bills");
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.support_agent, color: Colors.green),
            title: Text("Chat with Admin", style: GoogleFonts.poppins()),
            onTap: () {
              Navigator.pop(context);
              _startSupportChat();
            },
          ),

          const Divider(),

          // --- Portal Options ---
          ListTile(
            leading: const Icon(Icons.engineering, color: Colors.orange),
            title: Text("Worker Portal", style: GoogleFonts.poppins()),
            onTap: () {
              Navigator.pop(context);
              _showTechLogin(context);
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.admin_panel_settings,
              color: Colors.redAccent,
            ),
            title: Text("Admin Analytics", style: GoogleFonts.poppins()),
            onTap: () {
              Navigator.pop(context);
              _showAdminLogin(context);
            },
          ),

          const Spacer(), // Pushes logout to the bottom
          // ✅ LOGOUT OPTION ADDED BACK TO DRAWER
          const Divider(),
          ListTile(
            leading: Icon(
              _phone == null ? Icons.login : Icons.logout,
              color: _phone == null ? Colors.blue : Colors.redAccent,
            ),
            title: Text(
              _phone == null ? "Login" : "Logout",
              style: GoogleFonts.poppins(
                color: _phone == null ? Colors.blue : Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              Navigator.pop(context); // Close drawer
              _handleLogout(); // Trigger the logout dialog logic
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _showBillHistorySheet(BuildContext context) async {
    List<OutageReport> history = await _db.getCustomerHistory(_phone!);
    List<OutageReport> completedJobs = history
        .where((r) => r.status == 'Completed')
        .toList();

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
              "Download Receipt",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Divider(),
            Expanded(
              child: completedJobs.isEmpty
                  ? const Center(child: Text("No completed jobs found."))
                  : ListView.builder(
                      itemCount: completedJobs.length,
                      itemBuilder: (context, index) {
                        final report = completedJobs[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.picture_as_pdf,
                            color: Colors.redAccent,
                          ),
                          title: Text(
                            "${report.outageType.toUpperCase()} Service",
                          ),
                          subtitle: Text(
                            report.timestamp.toString().substring(0, 10),
                          ),
                          trailing: const Icon(Icons.download),
                          onTap: () {
                            Navigator.pop(c);
                            _generatePdf(
                              "Technician",
                              report.preferredSlot ?? "N/A",
                              "SE-${report.key?.substring(0, 4) ?? '0000'}",
                              report.completionPin ?? "0000",
                              _type ?? "General Service",
                              _desc ?? "Service Request",
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLoginRequiredPopup(String action) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "Login Required",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          "You must login to $action. Please enter your 10-digit mobile number in the chat.",
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(c); // Close the dialog
              // ✅ Automatically trigger login flow
              setState(() {
                _state = ChatState.askingPhone;
                _messages.clear();
                _messages.add(
                  Message(
                    text:
                        "👋 Welcome! Please enter your 10-digit mobile number to login and $action.",
                    type: MessageType.agent,
                    timestamp: DateTime.now(),
                  ),
                );
              });
            },
            child: const Text("LOGIN"),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
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

  Widget _buildServiceDecisionButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() => _showServiceDecisionButtons = false);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) => HistoryScreen(phone: _phone!),
                  ),
                );
              },
              icon: const Icon(Icons.update),
              label: const Text("Update"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade100,
                foregroundColor: Colors.orange.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() => _showServiceDecisionButtons = false);
                _addMsg("New", MessageType.user);
                _addMsg("🏠 Please provide area Pincode.", MessageType.agent);
                _state = ChatState.verifyingPincode;
              },
              icon: const Icon(Icons.add_circle_outline),
              label: const Text("New"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade100,
                foregroundColor: Colors.blue.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestartButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _showRestartButtons = false;
                  _state = ChatState.selectingType;
                  _showServiceChips = true;
                });
                _addMsg("Yes", MessageType.user);
                _addMsg(
                  "Great! Which other service requires attention?",
                  MessageType.agent,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade100,
                foregroundColor: Colors.green.shade900,
              ),
              child: const Text("Yes"),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _showRestartButtons = false;
                  _showExitButton = true;
                  _state = ChatState.completed;
                });
                _addMsg("No", MessageType.user);
                _addMsg(
                  "Thank you for choosing ServeEasy! 👋",
                  MessageType.agent,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade100,
                foregroundColor: Colors.red.shade900,
              ),
              child: const Text("No"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExitButton() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ElevatedButton.icon(
        onPressed: () => SystemNavigator.pop(),
        icon: const Icon(Icons.exit_to_app),
        label: const Text("EXIT APPLICATION"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey.shade900,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  Widget _buildServiceChips() {
    List<String> services = ["Electricity", "Water", "Gas"];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: services
            .map(
              (s) => ActionChip(
                avatar: Icon(
                  s == "Electricity"
                      ? Icons.bolt
                      : s == "Water"
                      ? Icons.water_drop
                      : Icons.local_fire_department,
                  size: 16,
                ),
                label: Text(s, style: GoogleFonts.poppins(fontSize: 12)),
                onPressed: () {
                  _controller.text = s;
                  _handleSend();
                },
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildInputDock() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: "Type reply...",
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFF1F4F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onSubmitted: (_) => _handleSend(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF0061FF), Color(0xFF60EFFF)],
              ),
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _handleSend,
            ),
          ),
        ],
      ),
    );
  }

  // ... [Keep imports and previous Enums/Classes the same]

  @override
  Widget build(BuildContext context) {
    final bool isSupportMode = _state == ChatState.supportChat;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false, // Prevents the app from closing immediately
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return; // If it already popped, do nothing

        // Trigger your existing exit confirmation function
        _showExitConfirmation();
      },

      child: Scaffold(
        backgroundColor: isSupportMode
            ? (isDark ? const Color(0xFF101820) : const Color(0xFFE3F2FD))
            : (isDark ? const Color(0xFF121212) : const Color(0xFFF0F2F5)),
        drawer: _buildCustomerDrawer(context),

        // lib/main.dart - Inside _ChatScreenState's build method
        appBar: AppBar(
          toolbarHeight: 70,
          backgroundColor: const Color(0xFF0061FF),
          centerTitle: false,
          titleSpacing: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          systemOverlayStyle: SystemUiOverlayStyle.light,

          // ✅ PERMANENT MENU: Removed _handleBack logic to keep the drawer accessible
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),

          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 4),
              Image.asset(
                "assets/logo.png",
                height: 28,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.handyman, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 8),

              // ✅ FLEXIBLE: Prevents text from overlapping the "New" button
              Flexible(
                child: Text(
                  _state == ChatState.supportChat ? "Support" : "ServeEasy",
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          actions: [
            if (_phone != null)
              _buildAppBarAction(
                icon: Icons.add_circle_outline,
                label: "New",
                onTap: () {
                  setState(() {
                    _state = ChatState.verifyingPincode;
                    _addMsg("New Request", MessageType.user);
                    _addMsg(
                      "🏠 Please provide area Pincode.",
                      MessageType.agent,
                    );
                  });
                },
              ),
            _buildAppBarAction(
              icon: Icons.refresh,
              label: "Refresh",
              onTap: () async {
                if (_phone != null) {
                  var user = await _db.getCustomer(_phone!);
                  if (user != null) {
                    setState(() {
                      _name = user['name'];
                      _address = user['address'];
                      _pincode = user['pincode']?.toString();
                    });
                  }
                }
                setState(() {});
              },
            ),
            _buildAppBarAction(
              icon: _phone == null ? Icons.login : Icons.logout,
              label: _phone == null ? "Login" : "Logout",
              onTap: _handleLogout,
            ),
            const SizedBox(width: 4),
          ],
        ),

        body: Column(
          children: [
            // If in support mode, show a small indicator banner
            if (isSupportMode)
              Container(
                width: double.infinity,
                color: Colors.green.withOpacity(0.2),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: const Center(
                  child: Text(
                    "SECURE SUPPORT CHANNEL",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),

            Expanded(
              child: !isSupportMode
                  ? ListView.builder(
                      controller: _scrollController,
                      itemCount: _messages.length,
                      itemBuilder: (c, i) => _buildChatBubble(_messages[i]),
                    )
                  : StreamBuilder(
                      stream: _phone == null
                          ? null
                          : _db.getSupportChatStream(_phone!),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData ||
                            snapshot.data!.snapshot.value == null) {
                          return const Center(
                            child: Text("Say hello to Admin!"),
                          );
                        }

                        Map msgs = snapshot.data!.snapshot.value as Map;

                        // ✅ FIX: Filter out non-Map entries (like admin_last_read) before sorting
                        var sortedKeys =
                            msgs.keys.where((k) => msgs[k] is Map).toList()
                              ..sort((a, b) {
                                DateTime timeA = _parseDateTime(
                                  msgs[a]['timestamp'],
                                );
                                DateTime timeB = _parseDateTime(
                                  msgs[b]['timestamp'],
                                );
                                return timeA.compareTo(timeB);
                              });

                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: sortedKeys.length,
                          itemBuilder: (c, i) {
                            var m = msgs[sortedKeys[i]];
                            return _buildChatBubble(
                              Message(
                                text: m['text'] ?? "",
                                type: m['sender'] == 'admin'
                                    ? MessageType.agent
                                    : MessageType.user,
                                timestamp: _parseDateTime(m['timestamp']),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),

            if (_showServiceDecisionButtons) _buildServiceDecisionButtons(),
            if (_showRestartButtons) _buildRestartButtons(),
            if (_showExitButton) _buildExitButton(),
            if (_showServiceChips) _buildServiceChips(),

            _buildInputDock(),
          ],
        ),
      ),
    );
  }

  void _startSupportChat() async {
    // ✅ If not logged in, show pop-up requirement
    if (_phone == null) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Login Required"),
          content: const Text(
            "You must login to chat with our admin support. Please enter your 10-digit mobile number in the chat.",
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(c);
                // Trigger the login flow automatically
                setState(() {
                  _state = ChatState.askingPhone;
                  _messages.clear();
                  _messages.add(
                    Message(
                      text:
                          "👋 Please enter your 10-digit mobile number to login and start support.",
                      type: MessageType.agent,
                      timestamp: DateTime.now(),
                    ),
                  );
                });
              },
              child: const Text("ENTER NUMBER"),
            ),
          ],
        ),
      );
      return;
    }

    // Normal support chat entry for logged-in users
    setState(() => _state = ChatState.supportChat);
    await _db.updateUserLastRead(_phone!);
  }

  Widget _buildChatBubble(Message msg) {
    bool isAgent = msg.type == MessageType.agent;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: isAgent ? Alignment.centerLeft : Alignment.centerRight,
      child: Column(
        crossAxisAlignment: isAgent
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isAgent
                  ? (isDark ? const Color(0xFF1E1E1E) : Colors.white)
                  : const Color(0xFF0061FF),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: _renderFormattedText(
              msg.text,
              isAgent
                  ? (isDark ? Colors.white70 : Colors.black87)
                  : Colors.white,
            ),
          ),
          if (msg.isConfirmation)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: ElevatedButton.icon(
                onPressed: () => _generatePdf(
                  _selectedTech?.name ?? "Technician",
                  _slots.isNotEmpty ? _slots.first : "ASAP",
                  _currentBookingId ?? "SE-0000",
                  _currentPin ?? "0000",
                  _type ?? "General Service",
                  _desc ?? "Service Request",
                ),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("Download Receipt"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _renderFormattedText(String text, Color textColor) {
    List<TextSpan> spans = [];
    final RegExp boldRegex = RegExp(r'\*\*(.*?)\*\*');
    int lastMatchEnd = 0;
    for (final match in boldRegex.allMatches(text)) {
      if (match.start > lastMatchEnd)
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < text.length)
      spans.add(TextSpan(text: text.substring(lastMatchEnd)));
    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(color: textColor, fontSize: 14),
        children: spans,
      ),
    );
  }

  Future<void> _generatePdf(
    String? tName, // Changed to nullable for safety
    String slot,
    String bookingId,
    String pin,
    String? sType,
    String? sIssue,
  ) async {
    print("DEBUG: Technician name received is: '$tName'");
    final pdf = pw.Document();

    // Ensure we have a displayable name
    final displayName =
        (tName == null || tName.isEmpty || tName.toLowerCase() == "technician")
        ? "NOT ASSIGNED"
        : tName.toUpperCase();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                "SERVEEASY SERVICE RECEIPT",
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 20),
            pw.Text(
              "BOOKING ID: $bookingId",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              "CUSTOMER DETAILS",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              children: [
                _buildPdfRow("CUSTOMER NAME", _name?.toUpperCase() ?? "N/A"),
                _buildPdfRow("MOBILE NUMBER", _phone?.toUpperCase() ?? "N/A"),
                _buildPdfRow("ADDRESS", _address?.toUpperCase() ?? "N/A"),
                _buildPdfRow("AREA PINCODE", _pincode?.toUpperCase() ?? "N/A"),
                _buildPdfRow("COMPLETION PIN", pin),
              ],
            ),
            pw.SizedBox(height: 30),
            pw.Text(
              "SERVICE DETAILS",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              children: [
                _buildPdfRow(
                  "SERVICE TYPE",
                  sType?.toUpperCase() ?? "GENERAL SERVICE",
                ),
                _buildPdfRow("ISSUE", sIssue?.toUpperCase() ?? "NOT SPECIFIED"),
                _buildPdfRow(
                  "TECHNICIAN",
                  displayName,
                ), // Uses the safety-checked name
                _buildPdfRow("TIME SLOT", slot.toUpperCase()),
              ],
            ),
            pw.Spacer(),
            pw.Divider(),
            pw.Center(
              child: pw.Text(
                "Share PIN only after job is complete.",
                style: pw.TextStyle(fontSize: 10, color: PdfColors.red),
              ),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  pw.TableRow _buildPdfRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(value, style: pw.TextStyle(fontSize: 10)),
        ),
      ],
    );
  }

  void _handleLogout() {
    // ✅ If clicking "Login" while not authenticated
    if (_phone == null) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Welcome to ServeEasy"),
          content: const Text(
            "To access your history and chat with support, please enter your mobile number.",
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(c);
                setState(() {
                  _state = ChatState.askingPhone;
                  _messages.clear();
                  _messages.add(
                    Message(
                      text:
                          "👋 Welcome! Please enter your 10-digit mobile number to begin.",
                      type: MessageType.agent,
                      timestamp: DateTime.now(),
                    ),
                  );
                });
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    // ✅ Existing Logout confirmation for authenticated users
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Logout"),
        content: const Text(
          "Are you sure you want to logout? All current session data will be cleared.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              setState(() {
                _phone = null;
                _name = null;
                _address = null;
                _pincode = null;
                _state = ChatState.askingPhone;
                _messages.clear();
                _messages.add(
                  Message(
                    text:
                        "👋 Greatings user! Welcome to ServeEasy Support. Please enter your 10-digit mobile number.",
                    type: MessageType.agent,
                    timestamp: DateTime.now(),
                  ),
                );
              });
              Navigator.pop(c);
            },
            child: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAdminLogin(BuildContext context) {
    TextEditingController idCtrl = TextEditingController(),
        passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Admin Secure Portal"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(labelText: "Admin ID"),
            ),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (await _db.loginAdmin(idCtrl.text, passCtrl.text)) {
                Navigator.pop(c);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (c) => const AdminDashboard()),
                );
              }
            },
            child: const Text("Login"),
          ),
        ],
      ),
    );
  }

  void _showTechLogin(BuildContext context) {
    TextEditingController idCtrl = TextEditingController(),
        passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Technician Portal"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(labelText: "Technician ID"),
            ),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              var tech = await _db.loginTechnician(idCtrl.text, passCtrl.text);
              if (tech != null) {
                Navigator.pop(c);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) =>
                        TechnicianView(techId: tech.id, techName: tech.name),
                  ),
                );
              }
            },
            child: const Text("Login"),
          ),
        ],
      ),
    );
  }
}
