import 'package:chatwoot_sdk/chatwoot_callbacks.dart';
import 'package:chatwoot_sdk/chatwoot_client.dart';
import 'package:chatwoot_sdk/data/local/entity/chatwoot_message.dart';
import 'package:chatwoot_sdk/data/local/entity/chatwoot_user.dart';
import 'package:chatwoot_sdk/data/remote/chatwoot_client_exception.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

/// Chatwoot聊天界面 - 使用dash_chat_2重写
/// 提供现代化UI和稳定的消息处理
class ChatwootChatDash extends StatefulWidget {
  final String baseUrl;
  final String inboxIdentifier;
  final bool enablePersistence;
  final ChatwootUser? user;
  final PreferredSizeWidget? appBar;

  // 回调函数
  final void Function()? onWelcome;
  final void Function()? onPing;
  final void Function()? onConfirmedSubscription;
  final void Function()? onConversationStartedTyping;
  final void Function()? onConversationIsOnline;
  final void Function()? onConversationIsOffline;
  final void Function()? onConversationStoppedTyping;
  final void Function(ChatwootMessage)? onMessageReceived;
  final void Function(ChatwootMessage)? onMessageSent;
  final void Function(ChatwootMessage)? onMessageDelivered;
  final void Function(ChatwootMessage)? onMessageUpdated;
  final void Function(List<ChatwootMessage>)? onPersistedMessagesRetrieved;
  final void Function(List<ChatwootMessage>)? onMessagesRetrieved;
  final void Function(ChatwootClientException)? onError;
  final void Function(ChatwootClient client)? onClientCreated;
  final void Function(ChatwootClient? client)? onAttachmentPressed;

  const ChatwootChatDash({
    Key? key,
    required this.baseUrl,
    required this.inboxIdentifier,
    this.enablePersistence = true,
    this.user,
    this.appBar,
    this.onWelcome,
    this.onPing,
    this.onConfirmedSubscription,
    this.onMessageReceived,
    this.onMessageSent,
    this.onMessageDelivered,
    this.onMessageUpdated,
    this.onPersistedMessagesRetrieved,
    this.onMessagesRetrieved,
    this.onConversationStartedTyping,
    this.onConversationStoppedTyping,
    this.onConversationIsOnline,
    this.onConversationIsOffline,
    this.onError,
    this.onClientCreated,
    this.onAttachmentPressed,
  }) : super(key: key);

  @override
  State<ChatwootChatDash> createState() => _ChatwootChatDashState();
}

class _ChatwootChatDashState extends State<ChatwootChatDash> {
  List<ChatMessage> _messages = [];
  final idGen = Uuid();
  late final ChatUser _currentUser;
  ChatwootClient? _chatwootClient;
  late final ChatwootCallbacks _chatwootCallbacks;

  @override
  void initState() {
    super.initState();
    _initializeUser();
    _initializeCallbacks();
    _createChatwootClient();
  }

  void _initializeUser() {
    if (widget.user == null) {
      _currentUser = ChatUser(id: idGen.v4(), firstName: '游客');
    } else {
      _currentUser = ChatUser(
        id: widget.user!.identifier ?? idGen.v4(),
        firstName: widget.user!.name,
        profileImage: widget.user!.avatarUrl,
      );
    }
  }

  void _initializeCallbacks() {
    _chatwootCallbacks = ChatwootCallbacks(
      onWelcome: widget.onWelcome,
      onPing: widget.onPing,
      onConfirmedSubscription: widget.onConfirmedSubscription,
      onConversationStartedTyping: widget.onConversationStartedTyping,
      onConversationStoppedTyping: widget.onConversationStoppedTyping,
      onPersistedMessagesRetrieved: (persistedMessages) {
        if (widget.enablePersistence && persistedMessages.isNotEmpty) {
          _handleBatchMessages(persistedMessages);
        }
        widget.onPersistedMessagesRetrieved?.call(persistedMessages);
      },
      onMessagesRetrieved: (messages) {
        if (messages.isNotEmpty) {
          _handleBatchMessages(messages);
        }
        widget.onMessagesRetrieved?.call(messages);
      },
      onMessageReceived: (chatwootMessage) {
        _addMessage(_convertToChatMessage(chatwootMessage));
        widget.onMessageReceived?.call(chatwootMessage);
      },
      onMessageDelivered: (chatwootMessage, echoId) {
        _handleServerMessage(chatwootMessage, echoId);
        widget.onMessageDelivered?.call(chatwootMessage);
      },
      onMessageSent: (chatwootMessage, echoId) {
        _handleServerMessage(chatwootMessage, echoId);
        widget.onMessageSent?.call(chatwootMessage);
      },
      onMessageUpdated: (chatwootMessage) {
        _updateMessage(chatwootMessage);
        widget.onMessageUpdated?.call(chatwootMessage);
      },
      onConversationResolved: () {
        _addSystemMessage('会话已结束');
      },
      onError: (error) {
        debugPrint("Chatwoot Error: ${error.cause}");
        widget.onError?.call(error);

        if (error.type == ChatwootClientExceptionType.SEND_MESSAGE_FAILED) {
          _handleSendMessageFailed(error.data);
        }
      },
    );
  }

  void _createChatwootClient() {
    ChatwootClient.create(
      baseUrl: widget.baseUrl,
      inboxIdentifier: widget.inboxIdentifier,
      user: widget.user,
      enablePersistence: widget.enablePersistence,
      callbacks: _chatwootCallbacks,
    ).then((client) {
      setState(() {
        _chatwootClient = client;
        _chatwootClient!.loadMessages();
        widget.onClientCreated?.call(client);
      });
    }).onError((error, stackTrace) {
      widget.onError?.call(ChatwootClientException(
        error.toString(),
        ChatwootClientExceptionType.CREATE_CLIENT_FAILED,
      ));
      debugPrint("创建Chatwoot客户端失败: $error\\n$stackTrace");
    });
  }

  // 消息转换: ChatwootMessage → ChatMessage
  ChatMessage _convertToChatMessage(ChatwootMessage msg) {
    final user = msg.isMine ? _currentUser : _createChatUser(msg.sender);

    final messageId = msg.id.toString();
    final createdAt = DateTime.parse(msg.createdAt);

    // 映射消息状态
    MessageStatus status = MessageStatus.none;
    if (msg.isMine) {
      final msgStatus = msg.status?.toLowerCase();

      // 1. 如果服务器明确给了 read/seen，那肯定是已读
      if (msgStatus == "seen" || msgStatus == "read") {
        status = MessageStatus.read;
      } else {
        // 2. 启发式逻辑：如果列表后面已经有客服回话了，那这条消息肯定也是已读
        bool agentRepliedLater = false;
        final msgTime = DateTime.parse(msg.createdAt);

        for (var existingMsg in _messages) {
          // 如果有一条消息比当前消息晚，且不是我发的（是客服发的）
          if (existingMsg.createdAt.isAfter(msgTime) &&
              existingMsg.user.id != _currentUser.id) {
            agentRepliedLater = true;
            break;
          }
        }

        if (agentRepliedLater) {
          status = MessageStatus.read;
        } else {
          // 保底状态：只要有ID就是灰色双勾（已送达）
          status = MessageStatus.received;
        }
      }
    }

    // 检查是否有附件(图片)
    if (msg.attachments != null && msg.attachments!.isNotEmpty) {
      final attachment = msg.attachments!.first;
      final dataUrl = attachment['data_url'];

      if (dataUrl != null &&
          dataUrl is String &&
          dataUrl.isNotEmpty &&
          (dataUrl.startsWith('http://') || dataUrl.startsWith('https://'))) {
        return ChatMessage(
          user: user,
          createdAt: createdAt,
          text: msg.content ?? "",
          status: status,
          medias: [
            ChatMedia(
              url: dataUrl,
              fileName: dataUrl.split("/").last,
              type: MediaType.image,
            )
          ],
          customProperties: {'id': messageId},
        );
      }
    }

    // 文本消息
    return ChatMessage(
      user: user,
      createdAt: createdAt,
      text: msg.content ?? "",
      status: status,
      customProperties: {'id': messageId},
    );
  }

  ChatUser _createChatUser(dynamic sender) {
    if (sender == null) {
      return ChatUser(id: '0', firstName: '客服');
    }

    String? avatarUrl = sender.avatarUrl ?? sender.thumbnail;
    if (avatarUrl?.contains("?d=404") ?? false) {
      avatarUrl = null;
    }

    return ChatUser(
      id: sender.id?.toString() ?? '0',
      firstName: sender.name ?? '客服',
      profileImage: avatarUrl,
    );
  }

  void _handleBatchMessages(List<ChatwootMessage> messages) {
    final chatMessages =
        messages.map((msg) => _convertToChatMessage(msg)).toList();

    setState(() {
      // 合并消息并去重
      final allMessages = <String, ChatMessage>{};

      // 先添加现有消息
      for (var msg in _messages) {
        final id = msg.customProperties?['id'] as String?;
        if (id != null) allMessages[id] = msg;
      }

      // 再添加新消息
      for (var msg in chatMessages) {
        final id = msg.customProperties?['id'] as String?;
        if (id != null) allMessages[id] = msg;
      }

      // 按时间排序(最新的在前)
      _messages = allMessages.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  void _addMessage(ChatMessage message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  void _addSystemMessage(String text) {
    final systemMsg = ChatMessage(
      user: ChatUser(id: 'system', firstName: '系统'),
      createdAt: DateTime.now(),
      text: text,
      customProperties: {'isSystem': true},
    );
    _addMessage(systemMsg);
  }

  void _handleServerMessage(ChatwootMessage chatwootMessage, String echoId) {
    final serverId = chatwootMessage.id.toString();

    setState(() {
      final index = _messages.indexWhere(
        (msg) =>
            msg.customProperties?['id'] == echoId ||
            msg.customProperties?['id'] == serverId,
      );

      if (index != -1) {
        // 消息已存在：更新它，确保将乐观ID(echoId)替换为真实的serverId
        _messages[index] = _convertToChatMessage(chatwootMessage);
      } else {
        // 消息不存在：添加它 (处理图片附件或多端同步情况)
        _messages.insert(0, _convertToChatMessage(chatwootMessage));
      }
    });
  }

  void _updateMessage(ChatwootMessage chatwootMessage) {
    final messageId = chatwootMessage.id.toString();

    setState(() {
      final index = _messages.indexWhere(
        (msg) => msg.customProperties?['id'] == messageId,
      );

      if (index != -1) {
        _messages[index] = _convertToChatMessage(chatwootMessage);
      }
    });
  }

  void _handleSendMessageFailed(String echoId) {
    setState(() {
      final index = _messages.indexWhere(
        (msg) => msg.customProperties?['id'] == echoId,
      );

      if (index != -1) {
        // 标记消息为失败状态
        final failedMsg = _messages[index];
        _messages[index] = ChatMessage(
          user: failedMsg.user,
          createdAt: failedMsg.createdAt,
          text: failedMsg.text,
          medias: failedMsg.medias,
          customProperties: {
            ...?failedMsg.customProperties,
            'failed': true,
          },
        );
      }
    });
  }

  void _onSend(ChatMessage message) {
    if (_chatwootClient == null) return;

    // 立即显示在UI中(乐观更新)
    final echoId = idGen.v4();
    final optimisticMessage = ChatMessage(
      user: message.user,
      createdAt: message.createdAt,
      text: message.text,
      customProperties: {'id': echoId},
    );

    setState(() {
      _messages.insert(0, optimisticMessage);
    });

    // 发送到服务器
    _chatwootClient!.sendMessage(
      content: message.text,
      echoId: echoId,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 性能优化：在构建渲染树前，先找出最后一条客服消息的时间戳作为“已读基准线”
    DateTime? latestAgentMsgTime;
    for (var m in _messages) {
      if (m.user.id != _currentUser.id &&
          m.customProperties?['isSystem'] != true) {
        if (latestAgentMsgTime == null ||
            m.createdAt.isAfter(latestAgentMsgTime)) {
          latestAgentMsgTime = m.createdAt;
        }
      }
    }

    return Scaffold(
      appBar: widget.appBar,
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // 聊天消息列表
          Expanded(
            child: DashChat(
              currentUser: _currentUser,
              messages: _messages,
              onSend: _onSend,
              messageOptions: MessageOptions(
                showTime: true,
                timeFormat: DateFormat('HH:mm'),
                currentUserContainerColor: const Color(0xFF1E88E5),
                containerColor: const Color(0xFFFFFFFF),
                textColor: Colors.black87,
                currentUserTextColor: Colors.white,
                borderRadius: 16,
                messagePadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                maxWidth: MediaQuery.of(context).size.width * 0.7,
                showCurrentUserAvatar: false,
                showOtherUsersAvatar: true,
                messageTextBuilder: (message, previousMessage, nextMessage) {
                  // 判定是否逻辑已读：或是服务器说了已读，或是它的时间早于客服最后回复时间
                  final bool isRead = message.status == MessageStatus.read ||
                      (latestAgentMsgTime != null &&
                          (message.createdAt.isBefore(latestAgentMsgTime) ||
                              message.createdAt
                                  .isAtSameMomentAs(latestAgentMsgTime)));

                  return Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(
                        message.text,
                        style: TextStyle(
                          color: message.user.id == _currentUser.id
                              ? Colors.white
                              : Colors.black87,
                          fontSize: 15,
                        ),
                      ),
                      if (message.user.id == _currentUser.id &&
                          message.status != MessageStatus.none)
                        Padding(
                          padding: const EdgeInsets.only(left: 6, bottom: 2),
                          child: Icon(
                            isRead || message.status == MessageStatus.received
                                ? Icons.done_all
                                : Icons.check,
                            size: 14,
                            color: isRead
                                ? const Color(0xFF00E5FF) // 极亮青色，已读状态
                                : Colors.white38, // 灰色，仅送达状态
                          ),
                        ),
                    ],
                  );
                },
                avatarBuilder: (user, onPressAvatar, onLongPressAvatar) {
                  if (user.profileImage != null &&
                      user.profileImage!.isNotEmpty) {
                    return CircleAvatar(
                      backgroundImage: NetworkImage(user.profileImage!),
                      radius: 16,
                    );
                  } else {
                    return CircleAvatar(
                      backgroundColor: const Color(0xFF42A5F5),
                      radius: 16,
                      child: Text(
                        user.firstName?.substring(0, 1).toUpperCase() ?? '?',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    );
                  }
                },
              ),
              inputOptions: InputOptions(
                inputDecoration: InputDecoration(
                  hintText: '请输入消息...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                inputTextStyle: const TextStyle(fontSize: 15),
                alwaysShowSend: true,
                sendOnEnter: true, // 启用Ctrl+Enter发送
                leading: [
                  // 附件按钮
                  if (widget.onAttachmentPressed != null)
                    IconButton(
                      icon: const Icon(Icons.attach_file,
                          color: Color(0xFF1E88E5)),
                      onPressed: () =>
                          widget.onAttachmentPressed!(_chatwootClient),
                      tooltip: '发送附件',
                    ),
                ],
                sendButtonBuilder: (onSend) {
                  return IconButton(
                    icon: const Icon(Icons.send_rounded,
                        color: Color(0xFF1E88E5)),
                    onPressed: onSend,
                    tooltip: '发送',
                  );
                },
              ),
              messageListOptions: MessageListOptions(
                onLoadEarlier: () async {
                  // 加载更早的消息(可选实现)
                },
              ),
            ),
          ),
          // 表情选择器面板 - 暂时禁用，因为 dash_chat_2 不支持自定义textController
          // 粘贴图片功能将在主应用层通过 onAttachmentPressed 实现
        ],
      ),
    );
  }

  @override
  void dispose() {
    _chatwootClient?.dispose();
    super.dispose();
  }
}
