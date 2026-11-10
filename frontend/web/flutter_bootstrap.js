{{flutter_js}}
{{flutter_build_config}}

// Chrome can fail CanvasKit's GPU shader compilation on some devices and
// drivers, which presents as visible flickering during pointer movement or
// scrolling. Use CanvasKit's CPU path only for Chrome. Edge and other browsers
// retain the default hardware-accelerated renderer.
const userAgent = navigator.userAgent;
const isChrome = /Chrome\//.test(userAgent) && !/Edg\//.test(userAgent);

_flutter.loader.load({
  config: {
    canvasKitForceCpuOnly: isChrome,
  },
});
