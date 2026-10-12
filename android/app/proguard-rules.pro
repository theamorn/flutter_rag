# ONNX Runtime (MiniLM embeddings via flutter_onnxruntime) is called through
# JNI; R8 must not strip or rename it in release builds.
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
# ML Kit ships consumer rules. flutter_gemma_litertlm is a native-assets dylib
# and needs no rules (flutter_gemma README, "ProGuard/R8").
