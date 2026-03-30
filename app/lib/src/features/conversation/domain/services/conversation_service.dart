import 'package:flutter/foundation.dart';
import 'package:matrix/src/core/matrix_avatar_disk_cache.dart';
import 'package:matrix/src/core/timeline_local_hidden_store.dart';
import 'package:matrix/src/core/video_send_media_prep.dart'
    show AppTimelineSendPrep, isTimelineVideoSendCandidate;
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
        RoomLinkItem,
        RoomPollItem,
        RoomPowerLevelSettingsPatch,
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

  /// Public read receipt on the latest timeline event; updates SDK unread counts for the room.
  Future<void> markTimelineAsRead(String roomId) async {
    try {
      await matrixService.client.markTimelineAsRead(roomId: roomId);
    } catch (_) {
      // Best-effort; opening the room should not fail the UI if the homeserver rejects receipts.
    }
  }

  /// Sliding Sync: subscribe this room for full required state + latest events (multiverse / Element).
  Future<void> roomListSubscribeToRooms(String roomId) async {
    await matrixService.client.roomListSubscribeToRooms(roomId: roomId);
  }

  /// One [getRoomDetails] round-trip for header state and member avatars (avoid duplicate Rust work).
  Future<Result<({ConversationInfo info, RoomDetails details})>> loadRoomSnapshot(
    String roomId,
  ) async {
    final r = await getRoomDetails(roomId);
    return r.fold(
      (d) => Success(
        (
          info: ConversationInfo(
            id: d.roomId,
            name: d.displayName.trim().isNotEmpty
                ? d.displayName.trim()
                : roomId,
            topic: d.topic,
            memberCount: d.memberCount,
            isDirect: d.isDirect,
            avatarUrl: null,
          ),
          details: d,
        ),
      ),
      Failure.new,
    );
  }

  Future<ConversationInfo> loadRoomInfo(String roomId) async {
    final r = await loadRoomSnapshot(roomId);
    return r.fold((s) => s.info, (f) => throw f);
  }

  /// Queues send on the UI timeline (local echo). [eventId] is often empty until echoed; UI follows the timeline stream.
  ///
  /// When [replyToEventId] is set, sends an `m.in_reply_to` reply (requires a **server** event id).
  Future<Result<String>> sendMessage(
    String roomId,
    String content, {
    String? replyToEventId,
  }) async {
    try {
      final String eventId;
      if (replyToEventId != null && replyToEventId.isNotEmpty) {
        eventId = await matrixService.client.sendReply(
          roomId: roomId,
          content: content,
          replyToEventId: replyToEventId,
        );
      } else {
        eventId = await matrixService.client.sendMessage(
          roomId: roomId,
          content: content,
        );
      }
      return Success(eventId);
    } catch (e) {
      return Failure(Exception(e));
    }
  }

  /// [prep] from [AppTimelineSendPrep.prepareForSend] when the file was prepared in the UI; otherwise
  /// sends [originalFilePath] as-is (generic files). Disposes [prep] when non-null.
  ///
  /// On success, the Rust SDK writes **`file_upload_cache`** (`app_db.sqlite3`): plain rooms store
  /// **`file_mxc`** and thumbnail **`mxc`** (plus metadata) after main + thumbnail upload; encrypted
  /// rooms store `e2ee_msgtype_json` / `e2ee_thumbnail_json` when the event can be read back.
  Future<Result<Unit>> sendTimelineAttachment({
    required String roomId,
    required String originalFilePath,
    AppTimelineSendPrep? prep,
    String? caption,
    int? audioDurationMs,
    List<double>? audioWaveformNormalized,
    bool audioAsVoiceMessage = false,
    required void Function(FileSendProgress p) onProgress,
  }) async {
    if (prep != null) {
      return sendTimelineFileWithPrepared(
        roomId: roomId,
        prep: prep,
        caption: caption,
        audioDurationMs: audioDurationMs,
        audioWaveformNormalized: audioWaveformNormalized,
        audioAsVoiceMessage: audioAsVoiceMessage,
        onProgress: onProgress,
      );
    }
    return _sendTimelineFileWithPaths(
      roomId: roomId,
      filePath: originalFilePath,
      caption: caption,
      appThumbnailJpegPath: null,
      audioDurationMs: audioDurationMs,
      audioWaveformNormalized: audioWaveformNormalized,
      audioAsVoiceMessage: audioAsVoiceMessage,
      onProgress: onProgress,
    );
  }

  /// Sends after [AppTimelineSendPrep] (compress/thumbnail) was built by the UI. Disposes [prep] when done.
  Future<Result<Unit>> sendTimelineFileWithPrepared({
    required String roomId,
    required AppTimelineSendPrep prep,
    String? caption,
    int? audioDurationMs,
    List<double>? audioWaveformNormalized,
    bool audioAsVoiceMessage = false,
    required void Function(FileSendProgress p) onProgress,
  }) async {
    try {
      return await _sendTimelineFileWithPaths(
        roomId: roomId,
        filePath: prep.filePathToSend,
        caption: caption,
        appThumbnailJpegPath: prep.appThumbnailJpegPath,
        audioDurationMs: audioDurationMs,
        audioWaveformNormalized: audioWaveformNormalized,
        audioAsVoiceMessage: audioAsVoiceMessage,
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
    int? audioDurationMs,
    List<double>? audioWaveformNormalized,
    bool audioAsVoiceMessage = false,
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
      final wf = audioWaveformNormalized;
      final stream = matrixService.client.sendTimelineFileWithProgress(
        roomId: roomId,
        filePath: filePath,
        caption: caption,
        appThumbnailJpegPath: appThumbnailJpegPath,
        audioDurationMs:
            audioDurationMs == null ? null : BigInt.from(audioDurationMs),
        audioWaveformNormalized: wf == null || wf.isEmpty
            ? null
            : Float32List.fromList(wf),
        audioAsVoiceMessage: audioAsVoiceMessage,
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
            Exception(l.message.isEmpty ? 'Failed to send file' : l.message),
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
    int? audioDurationMs,
    List<double>? audioWaveformNormalized,
    bool audioAsVoiceMessage = false,
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
        audioDurationMs: audioDurationMs,
        audioWaveformNormalized: audioWaveformNormalized,
        audioAsVoiceMessage: audioAsVoiceMessage,
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

  /// Profile avatar bytes for an `mxc://` URI (thumbnail when the server provides one).
  ///
  /// On IO platforms, serves from
  /// `{matrix_media_cache}/images/downloads/avatars/` when already downloaded.
  Future<Result<Uint8List>> fetchUserAvatarThumbnail({
    required String mxcUri,
  }) async {
    try {
      if (kIsWeb || kIsWasm) {
        final bytes = await matrixService.client.fetchUserAvatarThumbnail(
          mxcUri: mxcUri,
        );
        return Success(bytes);
      }
      final bytes = await MatrixAvatarDiskCache.instance.loadOrFetch(
        mxcUri,
        () => matrixService.client.fetchUserAvatarThumbnail(mxcUri: mxcUri),
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
    int? audioDurationMs,
    List<double>? audioWaveformNormalized,
    bool audioAsVoiceMessage = false,
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
      final wf = audioWaveformNormalized;
      final eventId = await matrixService.client.sendTimelineFile(
        roomId: roomId,
        filePath: sendPath,
        caption: caption,
        appThumbnailJpegPath: appThumb,
        audioDurationMs:
            audioDurationMs == null ? null : BigInt.from(audioDurationMs),
        audioWaveformNormalized: wf == null || wf.isEmpty
            ? null
            : Float32List.fromList(wf),
        audioAsVoiceMessage: audioAsVoiceMessage,
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

  Future<void> toggleTimelineReaction({
    required String roomId,
    required Message message,
    required String reactionKey,
  }) async {
    await matrixService.client.toggleTimelineReaction(
      roomId: roomId,
      eventId: message.eventId,
      transactionId: message.transactionId,
      reactionKey: reactionKey,
    );
  }

  /// Redact the event for everyone in the room (`m.room.redaction`), or abort a local echo
  /// when only [transactionId] is set (matrix-sdk-ui timeline).
  Future<Result<Unit>> redactTimelineEvent({
    required String roomId,
    required String eventId,
    required String transactionId,
    String? reason,
  }) async {
    try {
      await matrixService.client.redactTimelineEvent(
        roomId: roomId,
        eventId: eventId,
        transactionId: transactionId,
        reason: reason,
      );
      return const Success(unit);
    } catch (e) {
      return Failure(Exception(_formatMatrixFrbError(e)));
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
      await TimelineLocalHiddenStore.ensureLoaded();
      final list = await matrixService.client.listRoomFiles(
        roomId: roomId,
        filter: filter,
      );
      return Success(
        list
            .where(
              (f) => !TimelineLocalHiddenStore.isHiddenEventOrTransaction(
                eventId: f.eventId,
                transactionId: f.transactionId,
              ),
            )
            .toList(),
      );
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<List<RoomLinkItem>>> listRoomLinks({
    required String roomId,
    required RoomFileFilter filter,
  }) async {
    try {
      await TimelineLocalHiddenStore.ensureLoaded();
      final list = await matrixService.client.listRoomLinks(
        roomId: roomId,
        filter: filter,
      );
      return Success(
        list
            .where(
              (item) => !TimelineLocalHiddenStore.isHiddenEventOrTransaction(
                eventId: item.eventId,
                transactionId: item.transactionId,
              ),
            )
            .toList(),
      );
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<List<RoomPollItem>>> listRoomPolls({
    required String roomId,
    required RoomFileFilter filter,
  }) async {
    try {
      await TimelineLocalHiddenStore.ensureLoaded();
      final list = await matrixService.client.listRoomPolls(
        roomId: roomId,
        filter: filter,
      );
      return Success(
        list
            .where(
              (p) => !TimelineLocalHiddenStore.isHiddenEventOrTransaction(
                eventId: p.eventId,
                transactionId: p.transactionId,
              ),
            )
            .toList(),
      );
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<Unit>> sendPoll({
    required String roomId,
    required String question,
    required List<String> answerTexts,
    required bool kindDisclosed,
    int maxSelections = 1,
  }) async {
    try {
      await matrixService.client.sendPoll(
        roomId: roomId,
        question: question,
        answerTexts: answerTexts,
        kindDisclosed: kindDisclosed,
        maxSelections: BigInt.from(maxSelections.clamp(1, 20)),
      );
      return const Success(unit);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<Unit>> sendPollResponse({
    required String roomId,
    required String pollStartEventId,
    required List<String> answerIds,
  }) async {
    try {
      await matrixService.client.sendPollResponse(
        roomId: roomId,
        pollStartEventId: pollStartEventId,
        answerIds: answerIds,
      );
      return const Success(unit);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<Unit>> kickRoomMember({
    required String roomId,
    required String userId,
  }) async {
    try {
      await matrixService.client.kickRoomMember(roomId: roomId, userId: userId);
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

  Future<Result<Unit>> inviteUserToRoom({
    required String roomId,
    required String userId,
  }) async {
    try {
      await matrixService.client.inviteUserToRoom(
        roomId: roomId,
        userId: userId,
      );
      return const Success(unit);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<Unit>> banRoomMember({
    required String roomId,
    required String userId,
  }) async {
    try {
      await matrixService.client.banRoomMember(roomId: roomId, userId: userId);
      return const Success(unit);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  Future<Result<Unit>> unbanRoomMember({
    required String roomId,
    required String userId,
  }) async {
    try {
      await matrixService.client.unbanRoomMember(roomId: roomId, userId: userId);
      return const Success(unit);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }

  /// Updates `m.room.power_levels` for the fields set in [patch] only.
  Future<Result<Unit>> applyRoomPowerLevelSettings({
    required String roomId,
    required RoomPowerLevelSettingsPatch patch,
  }) async {
    try {
      await matrixService.client.applyRoomPowerLevelSettings(
        roomId: roomId,
        patch: patch,
      );
      return const Success(unit);
    } catch (e) {
      return Failure(Exception('$e'));
    }
  }
}

String _formatMatrixFrbError(Object e) {
  final raw = '$e'.trim();
  if (raw.isEmpty) return 'Request failed';
  return raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
}
