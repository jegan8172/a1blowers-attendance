// Breakpoints per HRMS_PROJECT_BLUEPRINT.md, Section 3.
// mobile: < 600, tablet: 600-1023, desktop: >= 1024

class Breakpoints {
  Breakpoints._();

  static const double mobileMax = 599.0;
  static const double tabletMax = 1023.0;

  static bool isMobile(double width) => width <= mobileMax;
  static bool isTablet(double width) => width > mobileMax && width <= tabletMax;
  static bool isDesktop(double width) => width > tabletMax;
}

enum ScreenSize { mobile, tablet, desktop }

ScreenSize screenSizeOf(double width) {
  if (Breakpoints.isMobile(width)) return ScreenSize.mobile;
  if (Breakpoints.isTablet(width)) return ScreenSize.tablet;
  return ScreenSize.desktop;
}

/// KPI card column count per HRMS_PROJECT_BLUEPRINT.md, Section 3:
/// four columns on desktop, two on tablet/mobile, one on very narrow
/// devices (e.g. small phones in portrait, < 360px).
int kpiColumnsOf(double width) {
  if (width < 360) return 1;
  if (Breakpoints.isDesktop(width)) return 4;
  return 2;
}
