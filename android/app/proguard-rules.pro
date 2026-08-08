# R8 / ProGuard rules for release builds.

# ML Kit text recognition ships one artifact per script. The Flutter plugin's
# Java references all of them from a single initialize() switch, so R8 sees
# calls into Chinese, Devanagari, Japanese and Korean classes that aren't on
# the classpath and fails the build.
#
# Only the Latin recognizer is bundled, and it's the only one this app asks
# for — see `TextRecognitionScript.latin` in
# lib/features/reminders/data/medicine_label_scanner.dart. The other branches
# are unreachable, so warning about them is noise.
#
# If a script beyond Latin is ever needed (Devanagari would be the one, for
# Hindi labels), add the matching `com.google.mlkit:text-recognition-*`
# dependency in this module rather than relaxing anything here.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# On-device LLM inference (flutter_gemma_mediapipe). The package ships its
# own consumer rules and release builds generally work without these, but
# the native bridge is reached reflectively — when R8 does strip something
# it surfaces as an UnsatisfiedLinkError at model load, long after the
# build looked fine. Keeping them is cheap insurance for a path we can only
# test on a real device.
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**
