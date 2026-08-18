import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

/// Resolves the bytes behind a captured or picked file on any platform.
///
/// The OCR pipelines don't hold a file — they hold a *reference* to one, and
/// re-read it whenever they need the bytes. That matters because a failed
/// scan can be retried long after the picker closed, so the bytes have to be
/// obtainable again from the reference alone.
///
/// On Android/iOS that reference is a filesystem path and re-reading is just
/// a disk read. On web there is no filesystem, and what a reference means
/// depends on which picker produced it:
///
///  * `camera` and `image_picker` hand back a **blob URL**, which [XFile] can
///    re-read on demand — the same call that reads a path on mobile.
///  * `file_picker` hands back **bytes and a bare file name**, with no path
///    and no blob URL. Nothing can re-derive those bytes from the name, so
///    the bytes have to be kept when they're first seen.
///
/// [register] covers that last case; [read] hides the difference from
/// callers. On mobile nothing is ever registered and every read falls through
/// to [XFile], so this costs nothing there.
class MediaBytes {
  MediaBytes._();

  /// Bytes that can't be re-derived from their reference, keyed by it.
  ///
  /// Only ever populated on web, and only by pickers that don't give back a
  /// re-readable URL. Entries are small in number (one per upload in the
  /// session) but each is a whole file, so [forget] exists for callers that
  /// know an upload is finished with.
  static final Map<String, Uint8List> _kept = {};

  /// Keeps [bytes] so a later [read] of [ref] can find them.
  ///
  /// Call this wherever a picker gives bytes but no re-readable reference.
  /// Registering on a platform that doesn't need it is harmless but wasteful,
  /// so guard the call with `kIsWeb` where the mobile path has a real file.
  static void register(String ref, Uint8List bytes) {
    if (ref.isEmpty) return;
    _kept[ref] = bytes;
  }

  /// Drops the bytes held for [ref], if any.
  static void forget(String ref) => _kept.remove(ref);

  /// The bytes behind [ref], or null when they can't be read.
  ///
  /// Returns null rather than throwing: a missing capture is an ordinary
  /// outcome the pipelines already report as "couldn't read this", not an
  /// error worth unwinding the upload for.
  static Future<Uint8List?> read(String ref) async {
    if (ref.isEmpty) return null;

    final kept = _kept[ref];
    if (kept != null) return kept;

    // A filesystem path on mobile, a blob URL on web — XFile reads both.
    try {
      return await XFile(ref).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// A display file name for [ref].
  ///
  /// A path's last segment is its name; a bare name is already one. A blob
  /// URL has no name in it at all, which is why callers that have a real one
  /// from the picker should pass it to the pipeline instead of relying on
  /// this.
  static String nameFor(String ref) {
    final trimmed = ref.split('?').first;
    final segment = trimmed.split('/').last;
    return segment.isEmpty ? ref : segment;
  }

  /// Visible for tests: forget everything kept so far.
  static void resetForTest() => _kept.clear();
}
