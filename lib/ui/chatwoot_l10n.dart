import 'package:flutter_chat_ui/flutter_chat_ui.dart';

/// Base chat l10n containing all required variables to provide localized chatwoot chat
class ChatwootL10n extends ChatL10n {
  /// Accessibility label (hint) for the attachment button
  final String attachmentButtonAccessibilityLabel;

  /// Placeholder when there are no messages
  final String emptyChatPlaceholder;

  /// Accessibility label (hint) for the tap action on file message
  final String fileButtonAccessibilityLabel;

  /// Placeholder for the text field
  final String inputPlaceholder;

  /// Placeholder for the text field
  final String onlineText;

  /// Placeholder for the text field
  final String offlineText;

  /// Placeholder for the text field
  final String typingText;

  /// Accessibility label (hint) for the send button
  final String sendButtonAccessibilityLabel;

  /// Message when agent resolves conversation
  final String conversationResolvedMessage;

  /// Message when agent resolves conversation
  final String and;

  /// Message when agent resolves conversation
  final String isTyping;

  /// Message when agent resolves conversation
  final String others;

  /// Message when agent resolves conversation
  final String unreadMessagesLabel;

  /// Creates a new chatwoot l10n
  const ChatwootL10n(
      {this.attachmentButtonAccessibilityLabel = "发送附件",
      this.emptyChatPlaceholder = "暂无消息",
      this.fileButtonAccessibilityLabel = "文件",
      this.onlineText = "通常几小时内回复",
      this.offlineText = "当前暂无客服在线",
      this.typingText = "正在输入...",
      this.inputPlaceholder = "请输入消息...",
      this.sendButtonAccessibilityLabel = "发送",
      this.conversationResolvedMessage = "对话已结束",
      this.and = "和",
      this.isTyping = "正在输入...",
      this.others = "其他",
      this.unreadMessagesLabel = "未读消息"})
      : super(
            attachmentButtonAccessibilityLabel:
                attachmentButtonAccessibilityLabel,
            emptyChatPlaceholder: emptyChatPlaceholder,
            fileButtonAccessibilityLabel: fileButtonAccessibilityLabel,
            inputPlaceholder: inputPlaceholder,
            sendButtonAccessibilityLabel: sendButtonAccessibilityLabel,
            and: and,
            isTyping: isTyping,
            others: others,
            unreadMessagesLabel: unreadMessagesLabel);
}
