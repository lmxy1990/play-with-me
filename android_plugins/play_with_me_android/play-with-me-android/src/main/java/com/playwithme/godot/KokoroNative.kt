package com.playwithme.godot


internal class KokoroNative private constructor() {
    companion object {
        private const val TAG = "KokoroNative"
        private var loadError: String? = null

        val isAvailable: Boolean
            get() = loadError == null

        val unavailableReason: String
            get() = loadError ?: ""

        init {
            loadError = try {
                System.loadLibrary("onnxruntime")
                System.loadLibrary("sherpa-onnx-c-api")
                System.loadLibrary("playwithme_kokoro_jni")
                AndroidDebugLog.d(TAG, "native libraries loaded")
                null
            } catch (error: UnsatisfiedLinkError) {
                val message = error.message ?: "Sherpa/Kokoro native library is unavailable"
                AndroidDebugLog.d(TAG, "native libraries load failed: $message", error)
                message
            } catch (error: SecurityException) {
                val message = error.message ?: "Sherpa/Kokoro native library cannot be loaded"
                AndroidDebugLog.d(TAG, "native libraries load blocked: $message", error)
                message
            }
        }

        fun ensureAvailable() {
            val error = loadError
            if (error != null) {
                throw IllegalStateException("本地 Kokoro 库不可用：$error")
            }
        }

        @JvmStatic
        external fun nativeCreate(modelDir: String, numThreads: Int): Long

        @JvmStatic
        external fun nativeDestroy(handle: Long)

        @JvmStatic
        external fun nativeGenerateToFile(
            handle: Long,
            text: String,
            sid: Int,
            speed: Float,
            silenceScale: Float,
            outputPath: String
        ): IntArray
    }
}
