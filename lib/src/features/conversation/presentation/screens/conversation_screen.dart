import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix/src/features/conversation/domain/services/conversation_service.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen_wm.dart';
import 'package:matrix/src/features/conversation/routes/conversation_routes.dart';
import 'package:matrix/src/rust/matrix/timelines.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

ConversationScreenWM conversationScreenWMFactory(BuildContext context) {
  return ConversationScreenWM(ConversationScreenModel(ConversationService()));
}

class ConversationScreen extends ElementaryWidget<ConversationScreenWM>
    implements ConversationRoutes {
  const ConversationScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.status,
  }) : super(conversationScreenWMFactory);

  final String roomId;
  final String roomName;
  final ChatRoomStatus status;

  @override
  Widget build(ConversationScreenWM wm) {
    return TerminalScreen(
      title: roomName.toUpperCase(),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: wm.showRoomInfo,
          tooltip: 'Room Info',
        ),
      ],
      child: Column(
        children: [
          // Messages list
          Expanded(
            child: ValueListenableBuilder<ConversationState>(
              valueListenable: wm.roomState,
              builder: (context, state, child) {
                return state.when(
                  waitingForInvite:
                      () => const Center(
                        child: Text(
                          'WAITING FOR INVITE TO BE ACCEPTED...',
                          style: MatrixTheme.statusStyle,
                        ),
                      ),
                  loading:
                      () => const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                MatrixTheme.matrixGreen,
                              ),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'LOADING MESSAGES...',
                              style: MatrixTheme.statusStyle,
                            ),
                          ],
                        ),
                      ),
                  loaded: (messages, roomInfo) => _buildMessagesList(messages),
                  error:
                      (message) => Center(
                        child: TerminalContainer(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: MatrixTheme.errorRed,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'ERROR',
                                style: MatrixTheme.titleStyle.copyWith(
                                  color: MatrixTheme.errorRed,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                message,
                                style: MatrixTheme.bodyStyle,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              TerminalButton(
                                text: 'RETRY',
                                onPressed: wm.retry,
                                icon: Icons.refresh,
                              ),
                            ],
                          ),
                        ),
                      ),
                );
              },
            ),
          ),

          // Message input
          ValueListenableBuilder<bool>(
            valueListenable: wm.isInvited,
            builder: (context, isInvited, child) {
              if (isInvited) {
                return _acceptInviteWidget(wm);
              } else {
                return _buildMessageInput(wm);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(List<Message> messages) {
    if (messages.isEmpty) {
      return const Center(
        child: Text(
          'NO MESSAGES YET\nSTART THE CONVERSATION',
          style: MatrixTheme.captionStyle,
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        if ([
              MessageType.dateDivider,
              MessageType.readMarker,
            ].contains(message.messageType) ||
            message.content.isEmpty) {
          return const SizedBox.shrink();
        }
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(Message message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Message header
          Row(
            children: [
              Text(
                '> ${message.displayName}',
                style: MatrixTheme.messageAuthorStyle,
              ),
              const Spacer(),
              Text(
                _formatTime(message.timestamp),
                style: MatrixTheme.messageTimeStyle,
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Message content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: MatrixTheme.messageDecoration,
            child: Text(message.content, style: MatrixTheme.messageStyle),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput(ConversationScreenWM wm) {
    return Row(
      children: [
        // Terminal prompt
        const Text('> ', style: MatrixTheme.terminalPromptStyle),

        // Message input field
        Expanded(
          child: TextField(
            controller: wm.messageController,
            style: MatrixTheme.inputStyle,
            decoration: const InputDecoration(
              hintText: 'Type your message...',
              hintStyle: MatrixTheme.hintStyle,
              border: InputBorder.none,
              contentPadding: EdgeInsetsDirectional.only(start: 8),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: MatrixTheme.matrixGreen,
                  width: 0.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: MatrixTheme.matrixGreen,
                  width: 1,
                ),
              ),
            ),
            onSubmitted: (text) => wm.sendMessage(),
            maxLines: null,
          ),
        ),

        // Send button
        IconButton(
          icon: const Icon(Icons.send, color: MatrixTheme.matrixGreen),
          onPressed: wm.sendMessage,
          tooltip: 'Send Message',
        ),
      ],
    );
  }

  String _formatTime(BigInt timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${dateTime.day}/${dateTime.month} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  Widget _acceptInviteWidget(ConversationScreenWM wm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MatrixTheme.matrixGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'You have been invited to this room',
            style: MatrixTheme.messageStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TerminalButton(
                text: 'ACCEPT',
                onPressed: wm.acceptInvite,
                icon: Icons.check,
              ),
              TerminalButton(
                text: 'REJECT',
                onPressed: wm.rejectInvite,
                icon: Icons.close,
                isPrimary: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void goBack(BuildContext context) {
    NavigatorService.pop(context);
  }

  @override
  void showRoomInfo(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: MatrixTheme.terminalBackground,
            title: const Text('ROOM INFO', style: MatrixTheme.titleStyle),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Room: General Discussion', style: MatrixTheme.bodyStyle),
                SizedBox(height: 8),
                Text('Members: 42', style: MatrixTheme.bodyStyle),
                SizedBox(height: 8),
                Text(
                  'Topic: Welcome to the Matrix',
                  style: MatrixTheme.bodyStyle,
                ),
              ],
            ),
            actions: [
              TerminalButton(
                text: 'CLOSE',
                onPressed: () => Navigator.of(context).pop(),
                isPrimary: false,
              ),
            ],
          ),
    );
  }
}
