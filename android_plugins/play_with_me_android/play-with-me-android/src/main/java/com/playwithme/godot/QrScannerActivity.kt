package com.playwithme.godot

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.annotation.OptIn
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.common.InputImage
import org.json.JSONObject
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class QrScannerActivity : ComponentActivity() {
    private lateinit var cameraExecutor: ExecutorService
    private var finished = false
    private var analyzing = false
    private var frameCount = 0L
    private var lastIdleLogAtMs = 0L
    private var lastRejectedPayloadHash = ""
    private var lastRejectedLogAtMs = 0L
    private var hintView: TextView? = null

    private val scanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AndroidDebugLog.d(TAG, "scanner onCreate cameraPermission=${checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED}")
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            finishFailure("相机权限未授权")
            return
        }

        cameraExecutor = Executors.newSingleThreadExecutor()
        setContentView(buildContentView())
        startCamera()
    }

    override fun onDestroy() {
        AndroidDebugLog.d(TAG, "scanner onDestroy finished=$finished frames=$frameCount")
        super.onDestroy()
        if (::cameraExecutor.isInitialized) {
            cameraExecutor.shutdown()
        }
        scanner.close()
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        finishCancelled()
    }

    private fun buildContentView(): View {
        val root = FrameLayout(this)
        val preview = PreviewView(this).apply {
            id = PREVIEW_VIEW_ID
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        root.addView(preview)
        root.addView(ScanOverlayView(this))

        val cancel = TextView(this).apply {
            text = "关闭"
            textSize = 16f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(28, 14, 28, 14)
            background = RoundRectDrawable(0x66000000, 28f, 0x44FFFFFF, 2f)
            setOnClickListener { finishCancelled() }
        }
        val cancelParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.RIGHT
        )
        cancelParams.setMargins(0, 24, 30, 0)
        root.addView(cancel, cancelParams)

        val hint = TextView(this).apply {
            text = "对准房间二维码"
            textSize = 18f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            includeFontPadding = false
            setShadowLayer(8f, 0f, 2f, Color.BLACK)
        }
        hintView = hint
        val hintParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        )
        hintParams.setMargins(0, 0, 0, 46)
        root.addView(hint, hintParams)
        return root
    }

    private fun startCamera() {
        AndroidDebugLog.d(TAG, "startCamera requested continuous ImageAnalysis polling")
        val previewView = findViewById<PreviewView>(PREVIEW_VIEW_ID)
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }
                val imageAnalysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                    analyzeImage(imageProxy)
                }
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    this,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    imageAnalysis
                )
                AndroidDebugLog.d(TAG, "camera bound with QR-only analyzer")
            } catch (error: Exception) {
                Log.e(TAG, "camera start failed", error)
                finishFailure(error.message ?: "相机启动失败")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    @OptIn(ExperimentalGetImage::class)
    private fun analyzeImage(imageProxy: ImageProxy) {
        frameCount += 1
        if (finished || analyzing) {
            imageProxy.close()
            return
        }
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            logIdle("frame=$frameCount skipped: image=null")
            imageProxy.close()
            return
        }
        analyzing = true
        val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        scanner.process(image)
            .addOnSuccessListener { barcodes ->
                if (barcodes.isEmpty()) {
                    logIdle("frame=$frameCount no barcode")
                    return@addOnSuccessListener
                }
                AndroidDebugLog.d(TAG, "frame=$frameCount barcode_count=${barcodes.size}")
                for (barcode in barcodes) {
                    val payload = barcode.rawValue?.trim().orEmpty()
                    if (payload.isBlank()) {
                        continue
                    }
                    val rejectReason = joinPayloadRejectReason(payload)
                    if (rejectReason == null) {
                        AndroidDebugLog.d(TAG, "room QR accepted ${payloadInfo(payload)}")
                        setHintText("已识别房间二维码")
                        finishSuccess(payload)
                        return@addOnSuccessListener
                    }
                    logRejected(payload, rejectReason)
                }
            }
            .addOnFailureListener { error ->
                if (!finished) {
                    Log.e(TAG, "barcode analyzer failed", error)
                    finishFailure(error.message ?: "二维码识别失败")
                }
            }
            .addOnCompleteListener {
                analyzing = false
                imageProxy.close()
            }
    }

    private fun finishSuccess(payload: String) {
        if (finished) {
            return
        }
        finished = true
        AndroidDebugLog.d(TAG, "finishSuccess ${payloadInfo(payload)}")
        val data = Intent().putExtra(EXTRA_QR_PAYLOAD, payload)
        setResult(Activity.RESULT_OK, data)
        finish()
    }

    private fun finishFailure(message: String) {
        if (finished) {
            return
        }
        finished = true
        AndroidDebugLog.d(TAG, "finishFailure message=$message")
        val data = Intent().putExtra(EXTRA_QR_ERROR, message)
        setResult(RESULT_SCAN_ERROR, data)
        finish()
    }

    private fun finishCancelled() {
        if (finished) {
            return
        }
        finished = true
        AndroidDebugLog.d(TAG, "finishCancelled")
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    private fun joinPayloadRejectReason(payload: String): String? {
        val json = try {
            JSONObject(payload)
        } catch (_: Exception) {
            return "not_json"
        }
        val app = json.optString("app", "").trim()
        if (app != APP_ID) {
            return "app_mismatch:$app"
        }
        return when (val version = json.optInt("version", 0)) {
            LEGACY_VERSION -> {
                val host = json.optString("host", "").trim()
                val port = json.optInt("port", 0)
                if (host.isBlank() || !isValidPort(port)) "legacy_address_invalid" else null
            }
            VERSION -> {
                if (json.optString("format", "").trim() != FORMAT_SECURE) {
                    return "secure_format_invalid"
                }
                val host = json.optString("host", "").trim()
                val port = json.optInt("port", 0)
                val address = json.optString("address", "").trim()
                if ((host.isBlank() || !isValidPort(port)) && !looksLikeAddress(address)) {
                    return "secure_address_invalid"
                }
                val required = listOf("secretId", "iv", "cipher", "mac")
                for (field in required) {
                    if (json.optString(field, "").trim().isBlank()) {
                        return "secure_missing_$field"
                    }
                }
                null
            }
            else -> "unsupported_version:$version"
        }
    }

    private fun looksLikeAddress(address: String): Boolean {
        val colon = address.lastIndexOf(':')
        if (colon <= 0 || colon >= address.length - 1) {
            return false
        }
        val host = address.substring(0, colon).trim()
        val port = address.substring(colon + 1).trim().toIntOrNull() ?: return false
        return host.isNotBlank() && isValidPort(port)
    }

    private fun isValidPort(port: Int): Boolean {
        return port in 1..65535
    }

    private fun logIdle(message: String) {
        val now = System.currentTimeMillis()
        if (now - lastIdleLogAtMs < IDLE_LOG_INTERVAL_MS) {
            return
        }
        lastIdleLogAtMs = now
        AndroidDebugLog.d(TAG, message)
    }

    private fun logRejected(payload: String, reason: String) {
        setHintText("不是房间二维码")
        val now = System.currentTimeMillis()
        val hash = Integer.toHexString(payload.hashCode())
        if (hash == lastRejectedPayloadHash && now - lastRejectedLogAtMs < REJECT_LOG_INTERVAL_MS) {
            return
        }
        lastRejectedPayloadHash = hash
        lastRejectedLogAtMs = now
        AndroidDebugLog.d(TAG, "room QR rejected reason=$reason ${payloadInfo(payload)}")
    }

    private fun setHintText(text: String) {
        runOnUiThread {
            hintView?.text = text
        }
    }

    private fun payloadInfo(payload: String): String {
        return "chars=${payload.length} hash=${Integer.toHexString(payload.hashCode())}"
    }

    companion object {
        private const val TAG = "PlayWithMeQrScanner"
        private const val APP_ID = "chat_with_me"
        private const val LEGACY_VERSION = 1
        private const val VERSION = 2
        private const val FORMAT_SECURE = "lan_join_secure"
        private const val IDLE_LOG_INTERVAL_MS = 2000L
        private const val REJECT_LOG_INTERVAL_MS = 1500L
        const val EXTRA_QR_PAYLOAD = "com.playwithme.godot.EXTRA_QR_PAYLOAD"
        const val EXTRA_QR_ERROR = "com.playwithme.godot.EXTRA_QR_ERROR"
        const val RESULT_SCAN_ERROR = Activity.RESULT_FIRST_USER + 428
        private const val PREVIEW_VIEW_ID = 4287101
    }
}

private class ScanOverlayView(context: android.content.Context) : View(context) {
    private val dimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x88000000.toInt()
    }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 6f
    }
    private val cornerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF51D7FF.toInt()
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeWidth = 12f
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val size = (width.coerceAtMost(height) * 0.58f).coerceAtLeast(280f)
        val left = (width - size) * 0.5f
        val top = (height - size) * 0.5f
        val right = left + size
        val bottom = top + size
        canvas.drawRect(0f, 0f, width.toFloat(), top, dimPaint)
        canvas.drawRect(0f, bottom, width.toFloat(), height.toFloat(), dimPaint)
        canvas.drawRect(0f, top, left, bottom, dimPaint)
        canvas.drawRect(right, top, width.toFloat(), bottom, dimPaint)
        canvas.drawRoundRect(left, top, right, bottom, 22f, 22f, borderPaint)

        val corner = size * 0.18f
        canvas.drawLine(left, top, left + corner, top, cornerPaint)
        canvas.drawLine(left, top, left, top + corner, cornerPaint)
        canvas.drawLine(right, top, right - corner, top, cornerPaint)
        canvas.drawLine(right, top, right, top + corner, cornerPaint)
        canvas.drawLine(left, bottom, left + corner, bottom, cornerPaint)
        canvas.drawLine(left, bottom, left, bottom - corner, cornerPaint)
        canvas.drawLine(right, bottom, right - corner, bottom, cornerPaint)
        canvas.drawLine(right, bottom, right, bottom - corner, cornerPaint)
    }
}

private class RoundRectDrawable(
    private val fillColor: Int,
    private val radius: Float,
    private val strokeColor: Int,
    private val strokeWidth: Float,
) : android.graphics.drawable.Drawable() {
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = fillColor
        style = Paint.Style.FILL
    }
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = strokeColor
        style = Paint.Style.STROKE
        strokeWidth = this@RoundRectDrawable.strokeWidth
    }

    override fun draw(canvas: Canvas) {
        val rect = bounds
        canvas.drawRoundRect(
            rect.left.toFloat(),
            rect.top.toFloat(),
            rect.right.toFloat(),
            rect.bottom.toFloat(),
            radius,
            radius,
            fillPaint
        )
        canvas.drawRoundRect(
            rect.left.toFloat() + strokeWidth * 0.5f,
            rect.top.toFloat() + strokeWidth * 0.5f,
            rect.right.toFloat() - strokeWidth * 0.5f,
            rect.bottom.toFloat() - strokeWidth * 0.5f,
            radius,
            radius,
            strokePaint
        )
    }

    override fun setAlpha(alpha: Int) {
        fillPaint.alpha = alpha
        strokePaint.alpha = alpha
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) {
        fillPaint.colorFilter = colorFilter
        strokePaint.colorFilter = colorFilter
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun getOpacity(): Int = android.graphics.PixelFormat.TRANSLUCENT
}
