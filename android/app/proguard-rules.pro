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

# Scheduled reminders surviving a reboot (flutter_local_notifications).
#
# The plugin persists its pending notifications as JSON and reads them back
# with Gson through a `TypeToken<ArrayList<NotificationDetails>>`. TypeToken
# recovers the element type from the generic signature at runtime, and R8
# drops those signatures by default — so the release build threw
# "TypeToken must be created with a type argument" the moment
# ScheduledNotificationBootReceiver fired, on every boot and every package
# replace. The user saw a crash dialog; the real damage was that medication
# reminders were never rescheduled after a restart.
#
# -keepattributes Signature is the load-bearing line. The rest keeps the
# model classes Gson reflects over, and the TypeToken subclasses R8 would
# otherwise merge away.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
