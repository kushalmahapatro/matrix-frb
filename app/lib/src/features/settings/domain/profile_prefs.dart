import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/src/features/settings/domain/profile_local_cache.dart';
import 'package:matrix_sdk/matrix_sdk.dart';

/// Local cache of profile initials from global account data; notifies on change.
class ProfilePrefs extends ChangeNotifier {
  ProfilePrefs._();
  static final ProfilePrefs instance = ProfilePrefs._();

  String? _initialsOverride;
  String? _ownAvatarMxc;

  /// Non-empty initials from account data (for the logged-in user's avatar fallback).
  String? get initialsOverride => _initialsOverride;

  /// Account avatar MXC when timeline rows have not received `sender_avatar_mxc` yet.
  String? get ownAvatarMxc => _ownAvatarMxc;

  Future<void> refresh(MatrixClient client) async {
    try {
      final loggedIn = await client.isClientAuthenticated();
      if (!loggedIn) {
        _initialsOverride = null;
        _ownAvatarMxc = null;
        await ProfileLocalCache.clear();
        notifyListeners();
        return;
      }
      final v = await client.getProfileInitials();
      _initialsOverride =
          v?.trim().isEmpty == true ? null : v?.trim();
      String? mxc;
      try {
        final cached = await client.getCachedProfileAvatarMxc();
        if (cached != null && cached.trim().isNotEmpty) {
          mxc = cached.trim();
        }
      } catch (_) {}
      mxc ??= await client.getProfileAvatarMxc();
      _ownAvatarMxc = mxc?.trim().isEmpty == true ? null : mxc?.trim();
    } catch (_) {
      _initialsOverride = null;
      _ownAvatarMxc = null;
    }
    notifyListeners();
  }

  void setLocalInitials(String? v) {
    _initialsOverride = v?.trim().isEmpty == true ? null : v?.trim();
    notifyListeners();
  }

  /// Keep in sync after profile photo upload/remove (timeline may lag behind account).
  void setLocalAvatarMxc(String? mxc) {
    _ownAvatarMxc = mxc?.trim().isEmpty == true ? null : mxc?.trim();
    notifyListeners();
  }

  void clear() {
    _initialsOverride = null;
    _ownAvatarMxc = null;
    unawaited(ProfileLocalCache.clear());
    notifyListeners();
  }
}
