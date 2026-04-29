/// Native platform detection — compiled only when dart:io is available.
library;

import 'dart:io' show Platform;

bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;
