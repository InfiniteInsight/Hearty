# ONNX Runtime: classes accessed via JNI from native code; R8 cannot trace them.
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
