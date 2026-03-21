import 'dart:typed_data';

import 'package:matrix/src/core/video_send_media_prep.dart'
    show
        AppTimelineSendPrep,
        isTimelineVideoSendCandidate;
import 'package:matrix/src/features/conversation/domain/models/conversation_state.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix_sdk/matrix_sdk.dart'
    show
        FileSendPhase,
        FileSendProgress,
        Message,
        MessageUpdate,
        RoomDetails,
        RoomFileFilter,
        RoomFileItem,
        RoomUpdate;
import 'package:result_dart/result_dart.dart';

class ConversationService {
  ConversationService({required this.matrixService});
  final MatrixService matrixService;

  Future<Result<List<Message>>> loadMessages(String roomId) async {
    try {
      final messages = await matrixService.client.getTimelineItemsByRoomId(
        roomId: roomId,
      );
      return Success(messages);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Stream<MessageUpdate> subscribeToTimelineUpdates(String roomId) {
    return matrixService.client.subscribeToTimelineUpdates(roomId: roomId);
  }

  /// Canonical message list for the room from Rust (full list on every change).
  Stream<List<Message>> subscribeToTimelineList(String roomId) {
    return matrixService.client.subscribeToTimelineList(roomId: roomId);
  }

  /// Sliding Sync: subscribe this room for full required state + latest events (multiverse / Element).
  Future<void> roomListSubscribeToRooms(String roomId) async {
    await matrixService.client.roomListSubscribeToRooms(roomId: roomId);
  }

  Future<ConversationInfo> loadRoomInfo() async {
    return ConversationInfo(
      id: '1',
      name: 'Test Room',
      topic: 'Test Topic',
      memberCount: 10,
    );
  }

  /// Queues send on the UI timeline (local echo). [eventId] is often empty until echoed; UI follows the timeline stream.
  Future<Result<String>> sendMessage(String roomId, String content) async {
    try {
      final eventId = await matrixService.client.sendMessage(
        roomId: roomId,
        content: content,
      );
      return Success(eventId);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  /// [prep] from [AppTimelineSendPrep.prepareForSend] when the file was prepared in the UI; otherwise
  /// sends [originalFilePath] as-is (generic files). Disposes [prep] when non-null.
  Future<Result<Unit>> sendTimelineAttachment({
    required String roomId,
    required String originalFilePath,
    AppTimelineSendPrep? prep,
    String? caption,
    required void Function(FileSendProgress p) onProgress,
  }) async {
    if (prep != null) {
      return sendTimelineFileWithPrepared(
        roomId: roomId,
        prep: prep,
        caption: caption,
        onProgress: onProgress,
      );
    }
    return _sendTimelineFileWithPaths(
      roomId: roomId,
      filePath: originalFilePath,
      caption: caption,
      appThumbnailJpegPath: null,
      onProgress: onProgress,
    );
  }

  /// Sends after [AppTimelineSendPrep] (compress/thumbnail) was built by the UI. Disposes [prep] when done.
  Future<Result<Unit>> sendTimelineFileWithPrepared({
    required String roomId,
    required AppTimelineSendPrep prep,
    String? caption,
    required void Function(FileSendProgress p) onProgress,
  }) async {
    try {
      return await _sendTimelineFileWithPaths(
        roomId: roomId,
        filePath: prep.filePathToSend,
        caption: caption,
        appThumbnailJpegPath: prep.appThumbnailJpegPath,
        onProgress: onProgress,
      );
    } finally {
      prep.dispose();
    }
  }

  Future<Result<Unit>> _sendTimelineFileWithPaths({
    required String roomId,
    required String filePath,
    String? caption,
    String? appThumbnailJpegPath,
    required void Function(FileSendProgress p) onProgress,
  }) async {
    if (await isTimelineVideoSendCandidate(filePath, mimeType: null)) {
      if (appThumbnailJpegPath == null || appThumbnailJpegPath.isEmpty) {
        return Failure(
          Exception(
            'Video send requires a JPEG thumbnail for the timeline. '
            'Thumbnail generation failed — try another clip or format.',
          ),
        );
      }
    }
    try {
      FileSendProgress? last;
      final stream = matrixService.client.sendTimelineFileWithProgress(
        roomId: roomId,
        filePath: filePath,
        caption: caption,
        appThumbnailJpegPath: appThumbnailJpegPath,
      );
      await for (final p in stream) {
        last = p;
        onProgress(p);
      }
      final l = last;
      if (l == null) {
        return Failure(Exception('File send ended with no status'));
      }
      switch (l.phase) {
        case FileSendPhase.done:
          return const Success(unit);
        case FileSendPhase.cancelled:
          return Failure(Exception('Cancelled'));
        case FileSendPhase.failed:
          return Failure(
            Exception(
              l.message.isEmpty ? 'Failed to send file' : l.message,
            ),
          );
        case FileSendPhase.videoCompress:
        case FileSendPhase.mainUpload:
        case FileSendPhase.thumbnailUpload:
        case FileSendPhase.sendingMessage:
        case FileSendPhase.encryptedQueued:
          return Failure(Exception('File send ended unexpectedly'));
      }
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  /// Sends a file with byte-level progress on the Rust side. [onProgress] receives updates until a terminal
  /// phase ([FileSendPhase.done], [FileSendPhase.failed], [FileSendPhase.cancelled]) is delivered on the stream.
  Future<Result<Unit>> sendTimelineFileWithProgress({
    required String roomId,
    required String filePath,
    String? caption,
    /// From [XFile.mimeType] / picker when the path has no video extension (e.g. `image_picker_…`).
    String? mimeType,
    required void Function(FileSendProgress p) onProgress,
  }) async {
    AppTimelineSendPrep? prep;
    try {
      prep = await AppTimelineSendPrep.prepare(filePath, mimeType: mimeType);
    } catch (_) {
      prep?.dispose();
      prep = null;
    }
    if (await isTimelineVideoSendCandidate(filePath, mimeType: mimeType)) {
      final thumb = prep?.appThumbnailJpegPath;
      if (prep == null || thumb == null || thumb.isEmpty) {
        prep?.dispose();
        return Failure(
          Exception(
            'Video send requires a JPEG thumbnail for the timeline. '
            'Thumbnail generation failed — try another clip or format.',
          ),
        );
      }
    }
    final sendPath = prep?.filePathToSend ?? filePath;
    final appThumb = prep?.appThumbnailJpegPath;
    try {
      return await _sendTimelineFileWithPaths(
        roomId: roomId,
        filePath: sendPath,
        caption: caption,
        appThumbnailJpegPath: appThumb,
        onProgress: onProgress,
      );
    } finally {
      prep?.dispose();
    }
  }

  Future<void> cancelTimelineFileSend() async {
    await matrixService.client.cancelTimelineFileSend();
  }

  /// Decrypted media from the Rust SDK (works for encrypted rooms). Prefer thumbnail for large files.
  Future<Result<Uint8List>> fetchRoomMessageMedia({
    required String roomId,
    required String eventId,
    bool thumbnail = true,
  }) async {
    try {
      final bytes = await matrixService.client.fetchRoomMessageMedia(
        roomId: roomId,
        eventId: eventId,
        thumbnail: thumbnail,
      );
      return Success(bytes);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  /// Sends a local file on the timeline. Image/video thumbnails come from the `media` package
  /// ([AppTimelineSendPrep]); plain rooms reuse MXC by path+hash.
  Future<Result<String>> sendTimelineFile({
    required String roomId,
    required String filePath,
    String? caption,
    String? mimeType,
  }) async {
    AppTimelineSendPrep? prep;
    try {
      prep = await AppTimelineSendPrep.prepare(filePath, mimeType: mimeType);
    } catch (_) {
      prep?.dispose();
      prep = null;
    }
    if (await isTimelineVideoSendCandidate(filePath, mimeType: mimeType)) {
      final thumb = prep?.appThumbnailJpegPath;
      if (prep == null || thumb == null || thumb.isEmpty) {
        prep?.dispose();
        return Failure(
          Exception(
            'Video send requires a JPEG thumbnail for the timeline. '
            'Thumbnail generation failed — try another clip or format.',
          ),
        );
      }
    }
    final sendPath = prep?.filePathToSend ?? filePath;
    final appThumb = prep?.appThumbnailJpegPath;

    try {
      final eventId = await matrixService.client.sendTimelineFile(
        roomId: roomId,
        filePath: sendPath,
        caption: caption,
        appThumbnailJpegPath: appThumb,
      );
      return Success(eventId);
    } catch (e) {
      return Failure(Exception(e));
    } finally {
      prep?.dispose();
    }
  }

  Future<void> retryFailedSend({
    required String roomId,
    required String transactionId,
  }) async {
    await matrixService.client.retryFailedSend(
      roomId: roomId,
      transactionId: transactionId,
    );
  }

  /// Room update for the last sent message. Call after [sendMessage] succeeds.
  /// Requires flutter_rust_bridge_codegen to be run so [MatrixClient.takeLastSentRoomUpdate] exists.
  Future<RoomUpdate?> takeLastSentRoomUpdate() async {
    return matrixService.client.takeLastSentRoomUpdate();
  }

  Future<Result<String>> acceptInvite(String roomId) async {
    try {
      final result = await matrixService.client.joinRoom(roomId: roomId);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Future<Result<String>> rejectInvite(String roomId) async {
    try {
      final result = await matrixService.client.leaveRoom(roomId: roomId);
      return Success(result);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Future<Result<List<Message>>> fetchOlderMessages({
    required String roomId,
    int count = 50,
  }) async {
    try {
      final previousMessages = await matrixService.client.getOlderMessages(
        roomId: roomId,
        count: count,
      );
      return Success(previousMessages);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  Future<Result<RoomDetails>> getRoomDetails(String roomId) async {
    try {
      final d = await matrixService.client.getRoomDetails(roomId: roomId);
      return Success(d);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<List<RoomFileItem>>> listRoomFiles({
    required String roomId,
    required RoomFileFilter filter,
  }) async {
    try {
      final list = await matrixService.client.listRoomFiles(
        roomId: roomId,
        filter: filter,
      );
      return Success(list);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<Unit>> kickRoomMember({
    required String roomId,
    required String userId,
  }) async {
    try {
      await matrixService.client.kickRoomMember(
        roomId: roomId,
        userId: userId,
      );
      return const Success(unit);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<String>> leaveAndForgetRoom(String roomId) async {
    try {
      final id = await matrixService.client.leaveAndForgetRoom(roomId: roomId);
      return Success(id);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<String>> leaveRoomOnly(String roomId) async {
    try {
      final id = await matrixService.client.leaveRoom(roomId: roomId);
      return Success(id);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<Unit>> setRoomMemberPowerLevel({
    required String roomId,
    required String userId,
    required int powerLevel,
  }) async {
    try {
      await matrixService.client.setRoomMemberPowerLevel(
        roomId: roomId,
        userId: userId,
        powerLevel: powerLevel,
      );
      return const Success(unit);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }
}
