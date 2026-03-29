import 'package:shared_preferences/shared_preferences.dart';

const String kDesktopRoomListWidthPrefsKey = 'desktop_room_list_width';

const double kDesktopSidebarWidthDefault = 292;
const double kDesktopSidebarWidthMin = 220;
const double kDesktopSidebarWidthMax = 560;

double clampDesktopSidebarWidth(double w) => w.clamp(
      kDesktopSidebarWidthMin,
      kDesktopSidebarWidthMax,
    );

Future<double> loadDesktopSidebarWidth() async {
  final p = await SharedPreferences.getInstance();
  final v = p.getDouble(kDesktopRoomListWidthPrefsKey);
  if (v == null) return kDesktopSidebarWidthDefault;
  return clampDesktopSidebarWidth(v);
}

Future<void> saveDesktopSidebarWidth(double w) async {
  final p = await SharedPreferences.getInstance();
  await p.setDouble(kDesktopRoomListWidthPrefsKey, clampDesktopSidebarWidth(w));
}
