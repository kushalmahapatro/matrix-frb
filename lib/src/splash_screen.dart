import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:graphx/graphx.dart';
import 'package:matrix/main.dart';
import 'package:matrix/src/extensions/context_extension.dart';
import 'package:matrix/src/logging_service.dart';
// import 'package:matrix/src/matrix_sync_service.dart';
// import 'package:matrix/src/rust/api/matrix_client.dart';
import 'package:matrix/src/login_screen.dart';
import 'package:matrix/src/home_screen.dart';
import 'package:matrix/src/matrix_sync_service.dart';
// import 'package:matrix/src/rust/api/matrix_client.dart';
import 'package:matrix/src/rust/matrix/client.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:sqflite/sqflite.dart';

import 'rust/matrix/authentication.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _checkAuthentication();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    MatrixTheme.updatePlatformBrightness(context);

    super.didChangePlatformBrightness();
  }

  Future<void> _checkAuthentication() async {
    final String databasesPath = await getDatabasesPath();
    LoggingService.info(
      runtimeType.toString(),
      'Databases path: $databasesPath',
    );

    // final config = MatrixClientConfig(
    //   homeserverUrl: homeserverUrl,
    //   storagePath: databasesPath,
    // );

    final config = ClientConfig(
      sessionPath: databasesPath,
      homeserverUrl: homeserverUrl.toString(),
    );

    // Test Rust logging
    LoggingService.info(
      runtimeType.toString(),
      'Starting Matrix client initialization',
    );

    final initSuccess = await configureClient(config: config);
    LoggingService.info(runtimeType.toString(), 'Init result: $initSuccess');

    if (!mounted) return;

    try {
      final userLoggedIn = await isClientAuthenticated();

      if (!mounted) return;

      // Navigate to appropriate screen
      if (userLoggedIn) {
        MatrixSyncService().performInitialSync();

        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder:
                (context, animation, secondaryAnimation) => const HomeScreen(),
            transitionDuration: const Duration(milliseconds: 800),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder:
                (context, animation, secondaryAnimation) => const LoginScreen(),
            transitionDuration: const Duration(milliseconds: 800),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      // On error, navigate to login screen
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionDuration: const Duration(milliseconds: 800),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SceneBuilderWidget(
      builder:
          () => SceneController(
            back: MatrixRainDrawingScene(
              getMatrixCharacters(),
              backgroundColor: context.colors.onSurface,
              textColor: context.colors.surface,
            ),
          ),
      autoSize: true,
    );
  }
}

class MatrixRainDrawingScene extends GSprite {
  MatrixRainDrawingScene(
    this._matrixChars, {
    this.backgroundColor = Colors.black,
    this.textColor = Colors.white,
  });
  final List<String> _matrixChars;
  final Color backgroundColor;
  final Color textColor;

  late GSprite _container;
  late GBitmap _captured;
  // 20FPS
  static const _reRenderDuration = Duration(milliseconds: 100);
  Timer? _timer;
  final textStyle = MatrixTheme.matrixRainStyle;
  Size _charSize = Size.zero;
  final _random = Random();

  int _getRandomCharIndex() {
    return _random.nextInt(_matrixChars.length - 1);
  }

  @override
  void addedToStage() {
    super.addedToStage();

    // Initialize container
    _initContainer();

    // Clip stage to widget size
    stage?.maskBounds = true;

    // Set character size
    _setCharSize();

    // Calculate column count
    final columnCount = (stage!.stageWidth / _charSize.width).floor() + 1;

    // Generate starting random characters list and y positions
    final startRandomCharsList = List.generate(
      columnCount,
      (index) => _getRandomCharIndex(),
    );
    final yPos = _generateYPos(columnCount);

    // Start timer for periodic rendering
    _timer = Timer.periodic(_reRenderDuration, (_) async {
      try {
        await _draw(yPos, startRandomCharsList);
      } catch (e) {
        debugPrint('Error during draw: $e');
      }
    });
  }

  void _setCharSize() {
    final label = _getNormalGText('X');
    _charSize = Size(label.textWidth, label.textHeight);
  }

  /// Draws the Matrix rain effect.
  Future<void> _draw(List<double> yPos, List<int> startRandomCharsInt) async {
    /// we have to draw a rect (transparent), so the bounds are detected when
    /// capturing the snapshot.
    final dimBG = GSprite();
    dimBG.graphics
        .beginFill(backgroundColor.withValues(alpha: 0.1))
        .drawRect(0, 0, stage!.stageWidth, stage!.stageHeight)
        .endFill();
    _container.addChild(dimBG);
    Map<Offset, String> overlays = {};

    for (var i = 0; i < yPos.length; i++) {
      final cursor = yPos[i] ~/ _charSize.height;

      final x = i * (_charSize.width * 2);
      final text =
          _matrixChars[(startRandomCharsInt[i] + cursor) %
              (_matrixChars.length - 1)];

      final label = _getNormalGText(text);

      _container.addChild(label);
      label.setPosition(x + (label.textWidth / 2), yPos[i]);

      overlays.putIfAbsent(
        Offset(x + (label.textWidth / 2), yPos[i]),
        () => text,
      );
      // randomly reset the end of the column if it's at least 100px high
      if (yPos[i] > 100 + _random.nextDouble() * 10000) {
        yPos[i] = 0;
      } else {
        yPos[i] += _charSize.height;
      }
    }

    // Save snapshot and release resources
    await _saveAndRelease();

    // Draw white overlay characters
    _drawWhiteChars(overlays);
  }

  // Create a GText object with the given text and text style
  GText _getGText(String text, TextStyle textStyle) {
    return GText(text: text, textStyle: textStyle)
      ..validate()
      ..alignPivot();
  }

  // Create a GText object with the given text and the default text style
  GText _getNormalGText(String text) {
    return _getGText(text, textStyle);
  }

  Future<void> _saveAndRelease() async {
    /// get a Texture (Image) from the container GSprite,
    /// at 100% resolution (1x).
    /// This value should match the dpiScale of the screen.
    final texture = await _container.createImageTexture(false);

    /// potential bug in GraphX, we should reset the pivot point in the Texture.
    /// so it doesnt goes off-stage if we press/move away the screen area.
    texture.pivotX = texture.pivotY = 0;

    /// after capturing the Texture, we clear the drawn line... to start fresh.
    /// and not overload the CPU.
    _container.graphics.clear();
    _container.removeChildren(0, -1, true);
    removeChildren(0, -1, true);
    _initContainer();

    /// refresh the GBitmap with the new texture.
    _captured.texture = texture;
  }

  void _initContainer() {
    _container = GSprite();

    /// we have to draw a rect (transparent), so the bounds are detected when
    /// capturing the snapshot.
    _container.graphics
        .beginFill(Colors.red.withValues(alpha: 0))
        .drawRect(0, 0, stage!.stageWidth, stage!.stageHeight)
        .endFill();
    _captured = GBitmap();

    /// Increase the smoothing quality when painting the Image into the
    /// canvas.
    _captured.nativePaint.filterQuality = FilterQuality.high;
    addChild(_container);
    _container.addChild(_captured);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<double> _generateYPos(int columnCount) {
    return List<double>.generate(
      columnCount,
      (index) => (index * _charSize.height) * _random.nextDouble(),
    );
  }

  void _drawWhiteChars(Map<Offset, String> overlays) {
    for (int i = 0; i < overlays.length; i++) {
      final offset = overlays.keys.toList()[i];
      final text = overlays.values.toList()[i];
      final whiteLabel = _getGText(
        text,
        textStyle.copyWith(
          color: textColor.withValues(alpha: _random.nextDouble()),
          shadows: [
            Shadow(
              color: textColor.withValues(alpha: _random.nextDouble()),
              blurRadius: 10,
            ),
          ],
        ),
      );

      addChild(whiteLabel);
      whiteLabel.setPosition(offset.dx, offset.dy);
    }
  }
}

List<String> getMatrixCharacters() {
  return [
    'M',
    'Ї',
    'Љ',
    'Њ',
    'Ћ',
    'Ќ',
    'Ѝ',
    'Ў',
    'Џ',
    'Б',
    'Г',
    'Д',
    'Ж',
    'И',
    'Й',
    'Л',
    'П',
    'Ф',
    'Ц',
    'Ч',
    'Ш',
    'Щ',
    'Ъ',
    'Ы',
    'Э',
    'Ю',
    'Я',
    'в',
    'д',
    'ж',
    'з',
    'и',
    'й',
    'к',
    'л',
    'м',
    'н',
    'п',
    'т',
    'ф',
    'ц',
    'ч',
    'ш',
    'щ',
    'ъ',
    'ы',
    'ь',
    'э',
    'ю',
    'я',
    'ѐ',
    'ё',
    'ђ',
    'ѓ',
    'є',
    'ї',
    'љ',
    'њ',
    'ћ',
    'ќ',
    'ѝ',
    'ў',
    'џ',
    'Ѣ',
    'ѣ',
    'ѧ',
    'Ѯ',
    'ѱ',
    'Ѳ',
    'ѳ',
    'ҋ',
    'Ҍ',
    'ҍ',
    'Ҏ',
    'ҏ',
    'Ґ',
    'ґ',
    'Ғ',
    'ғ',
    'Ҕ',
    'ҕ',
    'Җ',
    'җ',
    'Ҙ',
    'ҙ',
    'Қ',
    'қ',
    'ҝ',
    'ҟ',
    'ҡ',
    'Ң',
    'ң',
    'Ҥ',
    'ҥ',
    'ҩ',
    'Ҫ',
    'ҫ',
    'Ҭ',
    'ҭ',
    'Ұ',
    'ұ',
    'Ҳ',
    'ҳ',
    'ҵ',
    'ҷ',
    'ҹ',
    'Һ',
    'ҿ',
    'Ӂ',
    'ӂ',
    'Ӄ',
    'ӄ',
    'ӆ',
    'Ӈ',
    'ӈ',
    'ӊ',
    'Ӌ',
    'ӌ',
    'ӎ',
    'Ӑ',
    'ӑ',
    'Ӓ',
    'ӓ',
    'Ӕ',
    'ӕ',
    'Ӗ',
    'ӗ',
    'Ә',
    'ә',
    'Ӛ',
    'ӛ',
    'Ӝ',
    'ӝ',
    'Ӟ',
    'ӟ',
    'ӡ',
    'Ӣ',
    'ӣ',
    'Ӥ',
    'ӥ',
    'Ӧ',
    'ӧ',
    'Ө',
    'ө',
    'Ӫ',
    'ӫ',
    'Ӭ',
    'ӭ',
    'Ӯ',
    'ӯ',
    'Ӱ',
    'ӱ',
    'Ӳ',
    'ӳ',
    'Ӵ',
    'ӵ',
    'Ӷ',
    'ӷ',
    'Ӹ',
    'ӹ',
    'Ӻ',
    'ӽ',
    'ӿ',
    'Ԁ',
    'ԍ',
    'ԏ',
    'Ԑ',
    'ԑ',
    'ԓ',
    'Ԛ',
    'ԟ',
    'Ԧ',
    'ԧ',
    'Ϥ',
    'ϥ',
    'ϫ',
    'ϭ',
    'ｩ',
    'ｪ',
    'ｫ',
    'ｬ',
    'ｭ',
    'ｮ',
    'ｯ',
    'ｰ',
    'ｱ',
    'ｲ',
    'ｳ',
    'ｴ',
    'ｵ',
    'ｶ',
    'ｷ',
    'ｸ',
    'ｹ',
    'ｺ',
    'ｻ',
    'ｼ',
    'ｽ',
    'ｾ',
    'ｿ',
    'ﾀ',
    'ﾁ',
    'ﾂ',
    'ﾃ',
    'ﾄ',
    'ﾅ',
    'ﾆ',
    'ﾇ',
    'ﾈ',
    'ﾉ',
    'ﾊ',
    'ﾋ',
    'ﾌ',
    'ﾍ',
    'ﾎ',
    'ﾏ',
    'ﾐ',
    'ﾑ',
    'ﾒ',
    'ﾓ',
    'ﾔ',
    'ﾕ',
    'ﾖ',
    'ﾗ',
    'ﾘ',
    'ﾙ',
    'ﾚ',
    'ﾛ',
    'ﾜ',
    'ﾝ',
    'ⲁ',
    'Ⲃ',
    'ⲃ',
    'Ⲅ',
    'Γ',
    'Δ',
    'Θ',
    'Λ',
    'Ξ',
    'Π',
    'Ѐ',
    'Ё',
    'Ђ',
    'Ѓ',
    'Є',
    'ⲉ',
    'Ⲋ',
    'ⲋ',
    'Ⲍ',
    'ⲍ',
    'ⲏ',
    'ⲑ',
    'ⲓ',
    'ⲕ',
    'ⲗ',
    'ⲙ',
    'ⲛ',
    'Ⲝ',
    'ⲝ',
    'ⲡ',
    'ⲧ',
    'ⲩ',
    'ⲫ',
    'ⲭ',
    'ⲯ',
    'ⳁ',
    'Ⳉ',
    'ⳉ',
    'ⳋ',
    'ⳤ',
    '⳥',
    '⳦',
    '⳨',
    '⳩',
    '∀',
    '∁',
    '∂',
    '∃',
    '∄',
    '∅',
    '∆',
    '∇',
    '∈',
    '∉',
    '∊',
    '∋',
    '∌',
    '∍',
    '∎',
    '∏',
    '∐',
    '∑',
    '∓',
    'ℇ',
    'ℏ',
    '℥',
    'Ⅎ',
    'ℷ',
    '⩫',
    '⨀',
    '⨅',
    '⨆',
    '⨉',
    '⨍',
    '⨎',
    '⨏',
    '⨐',
    '⨑',
    '⨒',
    '⨓',
    '⨔',
    '⨕',
    '⨖',
    '⨗',
    '⨘',
    '⨙',
    '⨚',
    '⨛',
    '⨜',
    '⨝',
    '⨿',
    '⩪',
  ];
}
