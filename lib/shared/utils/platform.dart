import 'package:universal_platform/universal_platform.dart';
import 'package:flutter/material.dart';

bool isSmartwatch(BuildContext context) {
  double screenWidth = MediaQuery.sizeOf(context).width;
  double screenHeight = MediaQuery.sizeOf(context).height;
  bool isSmallScreen = screenWidth < 250 && screenHeight < 250;

  bool isAndroid = UniversalPlatform.isAndroid;

  return isSmallScreen && isAndroid;
}

bool shouldUseDesktopLayout(BuildContext context) {
  double screenWidth = MediaQuery.sizeOf(context).width;
  double screenHeight = MediaQuery.sizeOf(context).height;
  bool isLargeScreen = screenWidth > 1000 && screenHeight > 1000;

  bool isLandscape = screenWidth > screenHeight;

  bool isDesktop = UniversalPlatform.isDesktop;

  // temporary solution to support postmarketos / etc on mobile
  bool isLinux = UniversalPlatform.isLinux;

  return isLargeScreen || (isDesktop && !isLinux) || isLandscape;
}

bool shouldUseMobileLayout(BuildContext context) {
  return !shouldUseDesktopLayout(context);
}
