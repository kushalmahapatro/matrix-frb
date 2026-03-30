import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted snapshot of own profile for instant UI; refreshed after server reads.
class ProfileLocalSnapshot {
  const ProfileLocalSnapshot({
    required this.displayName,
    required this.initials,
    required this.avatarMxc,
  });

  final String displayName;
  final String initials;
  final String avatarMxc;

  bool get isEmpty =>
      displayName.isEmpty && initials.isEmpty && avatarMxc.isEmpty;
}

class ProfileLocalCache {
  ProfileLocalCache._();

  static const _kDisplay = 'profile_local_display_name';
  static const _kInitials = 'profile_local_initials';
  static const _kAvatarMxc = 'profile_local_avatar_mxc';

  static Future<ProfileLocalSnapshot?> load() async {
    final p = await SharedPreferences.getInstance();
    final d = p.getString(_kDisplay) ?? '';
    final i = p.getString(_kInitials) ?? '';
    final m = p.getString(_kAvatarMxc) ?? '';
    if (d.isEmpty && i.isEmpty && m.isEmpty) return null;
    return ProfileLocalSnapshot(displayName: d, initials: i, avatarMxc: m);
  }

  static Future<void> save({
    required String displayName,
    required String initials,
    required String avatarMxc,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDisplay, displayName);
    await p.setString(_kInitials, initials);
    await p.setString(_kAvatarMxc, avatarMxc);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kDisplay);
    await p.remove(_kInitials);
    await p.remove(_kAvatarMxc);
  }

  /// Best-effort refresh from client: prefers SDK state-store avatar cache, then network.
  static Future<void> refreshFromClient(MatrixClient client) async {
    try {
      final loggedIn = await client.isClientAuthenticated();
      if (!loggedIn) {
        await clear();
        return;
      }
      final disk = await load();
      final name = await client.getDisplayName();
      final initials = await client.getProfileInitials();
      String? mxc;
      try {
        final cached = await client.getCachedProfileAvatarMxc();
        if (cached != null && cached.trim().isNotEmpty) {
          mxc = cached.trim();
        }
      } catch (_) {}
      mxc ??= await client.getProfileAvatarMxc();
      final mxcStr = mxc?.trim() ?? '';
      await save(
        displayName: name?.trim() ?? disk?.displayName ?? '',
        initials: initials?.trim() ?? disk?.initials ?? '',
        avatarMxc: mxcStr.isNotEmpty ? mxcStr : (disk?.avatarMxc ?? ''),
      );
    } catch (_) {}
  }
}
