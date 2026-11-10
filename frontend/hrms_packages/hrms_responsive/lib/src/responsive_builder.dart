import 'package:flutter/widgets.dart';
import 'breakpoints.dart';

/// Builds a different widget per [ScreenSize] using [LayoutBuilder].
/// Each portal's shells (admin top-nav/drawer, employee sidebar/no-sidebar)
/// are composed on top of this.
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context) mobile;
  final Widget Function(BuildContext context) tablet;
  final Widget Function(BuildContext context) desktop;

  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    required this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = screenSizeOf(constraints.maxWidth);
        switch (size) {
          case ScreenSize.mobile:
            return mobile(context);
          case ScreenSize.tablet:
            return tablet(context);
          case ScreenSize.desktop:
            return desktop(context);
        }
      },
    );
  }
}
