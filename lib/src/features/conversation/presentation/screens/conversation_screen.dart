import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/chat_lisitng/domain/models/chat_state.dart';
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart'
    hide MessageType;
import 'package:matrix/src/features/conversation/domain/services/conversation_service.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen_wm.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/pagianted_message_list.dart';
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
                  loaded: (messages, roomInfo) {
                    return PaginatedMessageList(
                      initialMessages: messages,
                      loadOlder: (Message oldest) async {
                        await wm.fetchOlderMessages(conversationId: roomId);
                        return [];
                      },
                      onVisibleRange:
                          (Message firstVisible, Message lastVisible) {},
                    );
                  },
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
