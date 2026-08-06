enum MessageRole { user, assistant }

/// Languages the assistant currently supports.
enum AssistantLanguage {
  english('en', 'English'),
  tamil('ta', 'தமிழ்'),
  hindi('hi', 'हिन्दी');

  const AssistantLanguage(this.code, this.label);
  final String code;
  final String label;
}

/// A single message in an assistant conversation.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.language,
    this.isStreaming = false,
  });

  final String id;
  final MessageRole role;
  final String content;
  final AssistantLanguage language;
  final bool isStreaming;

  bool get isUser => role == MessageRole.user;
}
