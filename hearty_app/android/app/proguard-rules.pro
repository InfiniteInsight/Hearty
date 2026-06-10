# ONNX Runtime: classes accessed via JNI from native code; R8 cannot trace them.
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }

# flutter_local_notifications serializes scheduled notifications with Gson +
# TypeToken. In release builds R8 strips the generic Signature attribute (and
# can rename the TypeToken subclasses), so loadScheduledNotifications() throws
# "Missing type parameter." at startup — NotificationService.init() then never
# completes and the app hangs on the Flutter splash. Keep the generic signatures
# and the relevant classes. (Canonical flutter_local_notifications R8 fix.)
-keepattributes Signature
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
