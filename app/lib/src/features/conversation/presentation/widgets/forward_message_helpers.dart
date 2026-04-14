import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix_sdk/matrix_sdk.dart'
    show Message, MessageType, RoomMessageKind;

/// Plain-text body for a forwarded Matrix row (no rich reply / attachment re-upload).
String formatMessageBodySnippet(Message m) {
  final t = m.content.trim();
  if (t.isNotEmpty) return t;
  switch (m.roomMsgKind) {
    case RoomMessageKind.image:
      return '[Image]';
    case RoomMessageKind.video:
      return '[Video]';
    case RoomMessageKind.audio:
      return '[Audio]';
    case RoomMessageKind.file:
      return '[File]';
    case RoomMessageKind.poll:
      return '[Poll]';
    case RoomMessageKind.call:
      return '[Call]';
    case RoomMessageKind.text:
    case RoomMessageKind.other:
      return '[Message]';
  }
}

/// Full plain-text payload sent with [sendMessage] to the target room.
String buildForwardedMessagePlainText(Message m) {
  final from = m.sender.trim().isNotEmpty ? m.sender : m.senderUserId;
  final uid = m.senderUserId.trim();
  final body = formatMessageBodySnippet(m);
  final buf = StringBuffer()
    ..writeln('──────── Forwarded message ────────')
    ..writeln('From: $from${uid.isNotEmpty && uid != from ? ' ($uid)' : ''}')
    ..writeln(body);
  return buf.toString().trimRight();
}

bool messageCanBeForwarded(Message m) {
  if (m.isRedacted) return false;
  if (TimelineLocalHiddenStore.isHidden(m)) return false;
  if (m.messageType != MessageType.message) return false;
  return true;
}
