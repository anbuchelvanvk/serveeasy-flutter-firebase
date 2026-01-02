enum MessageType { user, agent }

class Message {
  final String text;
  final MessageType type;
  final DateTime timestamp;
  final bool isConfirmation; // This field is required for the PDF button

  Message({
    required this.text,
    required this.type,
    required this.timestamp,
    this.isConfirmation = false, 
  });
}