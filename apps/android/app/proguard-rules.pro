# Keep ONNX Runtime JNI classes and callbacks
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Prevent ART lock verification slowdowns on Jetpack Compose SnapshotStateList
-keep class androidx.compose.runtime.snapshots.** { *; }
