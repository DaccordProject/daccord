/// Directory detection for files dropped onto the composer.
///
/// `desktop_drop` only types directories as `DropItemDirectory` on macOS and
/// web — its shared `performOperation` handler, which Linux and Windows both
/// use, wraps every dropped path in a `DropItemFile` with no directory check.
/// Without this, a folder dropped on Linux or Windows falls through to
/// `XFile.length()`, which throws `FileSystemException: Is a directory`, and
/// the composer reports it as an unreadable file — telling the user to "copy it
/// to local storage and try again", which cannot help.
library;

export 'dropped_entity_stub.dart' if (dart.library.io) 'dropped_entity_io.dart';
