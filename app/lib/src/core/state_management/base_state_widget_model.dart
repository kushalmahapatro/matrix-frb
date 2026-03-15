import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

abstract class BaseWidgetModel<
  W extends ElementaryWidget,
  M extends ElementaryModel
>
    extends WidgetModel<W, M>
    with WidgetsBindingObserver {
  BaseWidgetModel(super.model);

  @override
  void initWidgetModel() {
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      super.initWidgetModel();
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
}
