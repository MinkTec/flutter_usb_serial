/// Stub for platform detection — used on web where dart:io is unavailable.
library;

/// Always false on web.
bool get isDesktop => false;
