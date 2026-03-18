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
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart';

ConversationScreenWM conversationScreenWMFactory(BuildContext context) {
  return ConversationScreenWM(
    ConversationScreenModel(
      ConversationService(matrixService: MatrixService()),
    ),
  );
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
                final theme = Theme.of(context);
                return state.when(
                  waitingForInvite: () => Center(
                    child: Text(
                      'WAITING FOR INVITE TO BE ACCEPTED...',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  loading: () => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'LOADING MESSAGES...',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  loaded: (messages, roomInfo) {
                    return PaginatedMessageList(
                      initialMessages: messages,
                      loadOlder: (Message oldest) async {
                        return await wm.fetchOlderMessages(
                          conversationId: roomId,
                          limit: 50,
                        );
                      },
                      onVisibleRange:
                          (Message firstVisible, Message lastVisible) {},
                    );
                  },
                  error: (message) => Center(
                    child: TerminalContainer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.error,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'ERROR',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            message,
                            style: theme.textTheme.bodyMedium,
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
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Row(
          children: [
            Text('> ', style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            )),
            Expanded(
              child: TextField(
                controller: wm.messageController,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Type your message...',
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsetsDirectional.only(start: 8),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 0.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 1,
                    ),
                  ),
                ),
                onSubmitted: (_) => wm.sendMessage(),
                maxLines: null,
              ),
            ),
            IconButton(
              icon: Icon(Icons.send, color: theme.colorScheme.primary),
              onPressed: wm.sendMessage,
              tooltip: 'Send Message',
            ),
          ],
        );
      },
    );
  }

  Widget _acceptInviteWidget(ConversationScreenWM wm) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                'You have been invited to this room',
                style: theme.textTheme.bodyMedium,
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
      },
    );
  }

  @override
  void goBack(BuildContext context) {
    NavigatorService.pop(context);
  }

  @override
  void showRoomInfo(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        title: Text('ROOM INFO', style: theme.textTheme.titleLarge),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room: General Discussion', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('Members: 42', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('Topic: Welcome to the Matrix', style: theme.textTheme.bodyMedium),
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
