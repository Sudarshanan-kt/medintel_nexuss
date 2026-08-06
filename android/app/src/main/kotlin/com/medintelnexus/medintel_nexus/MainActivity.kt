package com.medintelnexus.medintel_nexus

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native SMS + phone-call channel for the Emergency SOS feature.
 *
 * Why native code instead of a plugin: this needs to actually place a call
 * (ACTION_CALL) and send an SMS (SmsManager) with zero user interaction,
 * which no maintained Flutter plugin currently does reliably — the closest
 * ones (`telephony`, `sms_advanced`) haven't been updated since 2022/2023
 * and predate Android 12's mandatory PendingIntent mutability flags, so
 * they commonly crash on modern devices. This channel avoids the whole
 * problem by never creating a PendingIntent (delivery/sent callbacks are
 * skipped — SmsManager accepts null for both, which is fine here since we
 * only need best-effort delivery, not a receipt).
 *
 * Both android.permission.SEND_SMS and android.permission.CALL_PHONE are
 * "dangerous" runtime permissions Google Play restricts heavily for apps
 * not registered as the default SMS/phone handler — see the exception-form
 * process at https://support.google.com/googleplay/android-developer/answer/10467955
 * if this is ever published, rather than sideloaded for personal/demo use.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "medintel/sos"
    private val permissionRequestCode = 4821
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermissions" -> result.success(hasAllPermissions())
                    "requestPermissions" -> requestPermissions(result)
                    "sendSms" -> {
                        val phone = call.argument<String>("phone")
                        val message = call.argument<String>("message")
                        result.success(sendSmsNative(phone, message))
                    }
                    "placeCall" -> {
                        val phone = call.argument<String>("phone")
                        result.success(placeCallNative(phone))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasAllPermissions(): Boolean {
        val sms = ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
        val call = ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
        return sms == PackageManager.PERMISSION_GRANTED && call == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (hasAllPermissions()) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.SEND_SMS, Manifest.permission.CALL_PHONE),
            permissionRequestCode,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            pendingPermissionResult?.success(hasAllPermissions())
            pendingPermissionResult = null
        }
    }

    /** Sends [message] to [phone] silently — no compose UI, no PendingIntent. */
    private fun sendSmsNative(phone: String?, message: String?): Boolean {
        if (phone.isNullOrBlank() || message.isNullOrBlank()) return false
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return try {
            val smsManager: SmsManager =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    getSystemService(SmsManager::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getDefault()
                }
            // Long messages (this one includes a maps link) need to be split
            // into parts — sendMultipartTextMessage handles that safely,
            // unlike sendTextMessage which silently truncates at 160 chars.
            val parts = smsManager.divideMessage(message)
            smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Places a call to [phone] directly — no dialer screen, no tap. */
    private fun placeCallNative(phone: String?): Boolean {
        if (phone.isNullOrBlank()) return false
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return try {
            val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$phone"))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
