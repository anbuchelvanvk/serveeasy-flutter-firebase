import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'database_service.dart';

class AdminSupportView extends StatefulWidget {
  const AdminSupportView({super.key});
  @override
  State<AdminSupportView> createState() => _AdminSupportViewState();
}

class _AdminSupportViewState extends State<AdminSupportView> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _replyController = TextEditingController();
  String? _activeUserId;

  DateTime _parseDateTime(dynamic timestamp) {
    if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (timestamp is String)
      return DateTime.tryParse(timestamp) ?? DateTime.now();
    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: Text(
          "Support Center 💬",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF0061FF),
        iconTheme: const IconThemeData(color: Colors.white),
        // Mobile: Show back arrow if chat is open to return to list
        leading: (!isDesktop && _activeUserId != null)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _activeUserId = null),
              )
            : null,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            // Mobile View
            return _activeUserId == null
                ? _buildUserList()
                : _buildChatWindow();
          } else {
            // Desktop Split View
            return Row(
              children: [
                Expanded(flex: 2, child: _buildUserList()),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 5,
                  child: _activeUserId == null
                      ? const Center(
                          child: Text("Select a user to view messages"),
                        )
                      : _buildChatWindow(),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildUserList() {
    return Container(
      color: Colors.white,
      child: StreamBuilder(
        stream: _db.getAllSupportChats(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: Text("No active chats"));
          }
          Map chats = snapshot.data!.snapshot.value as Map;

          return ListView(
            children: chats.keys.map((uid) {
              Map userData = chats[uid] is Map ? chats[uid] : {};
              int lastRead = userData['admin_last_read'] ?? 0;

              // ✅ Unread Badge Logic
              int unreadCount = 0;
              userData.forEach((key, value) {
                if (value is Map && value['sender'] == 'user') {
                  int ts = value['timestamp'] is int ? value['timestamp'] : 0;
                  if (ts > lastRead) unreadCount++;
                }
              });

              return ListTile(
                leading: Stack(
                  children: [
                    const CircleAvatar(child: Icon(Icons.person_outline)),
                    if (unreadCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            "$unreadCount",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(
                  uid.toString(),
                  style: TextStyle(
                    fontWeight: unreadCount > 0
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  unreadCount > 0 ? "New message received" : "Chat History",
                  style: TextStyle(
                    color: unreadCount > 0 ? Colors.blue : Colors.grey,
                    fontSize: 12,
                  ),
                ),
                selected: _activeUserId == uid,
                onTap: () {
                  setState(() => _activeUserId = uid.toString());
                  _db.updateAdminLastRead(uid.toString()); // Mark as read
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildChatWindow() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder(
            stream: _db.getSupportChatStream(_activeUserId!),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.snapshot.value == null)
                return const SizedBox();
              Map msgs = snapshot.data!.snapshot.value as Map;

              // ✅ Filter metadata keys to prevent the crash
              var sortedKeys = msgs.keys.where((k) => msgs[k] is Map).toList()
                ..sort(
                  (a, b) => _parseDateTime(
                    msgs[a]['timestamp'],
                  ).compareTo(_parseDateTime(msgs[b]['timestamp'])),
                );

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sortedKeys.length,
                itemBuilder: (c, i) {
                  var m = msgs[sortedKeys[i]];
                  bool isAdmin = m['sender'] == 'admin';
                  return _buildBubble(m['text'] ?? "", isAdmin);
                },
              );
            },
          ),
        ),
        _buildReplyInput(),
      ],
    );
  }

  Widget _buildBubble(String text, bool isAdmin) {
    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isAdmin ? const Color(0xFF0061FF) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isAdmin ? 12 : 0),
            bottomRight: Radius.circular(isAdmin ? 0 : 12),
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
        ),
        child: Text(
          text,
          style: TextStyle(color: isAdmin ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  Widget _buildReplyInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _replyController,
              decoration: InputDecoration(
                hintText: "Type reply...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFFF1F4F9),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: const Color(0xFF0061FF),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: () {
                if (_replyController.text.isNotEmpty && _activeUserId != null) {
                  _db.sendAdminReply(_activeUserId!, _replyController.text);
                  _replyController.clear();
                  _db.updateAdminLastRead(_activeUserId!);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
