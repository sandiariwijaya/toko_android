package com.sandi.aplikasi_toko

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.provider.Settings
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "toko/native"
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val pickCode = 7311

    private var socket: BluetoothSocket? = null
    private var out: OutputStream? = null
    private var connectedAddress: String? = null
    private var pendingPick: MethodChannel.Result? = null

    private fun adapter(): BluetoothAdapter? {
        val m = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return m?.adapter
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                "deviceId" -> {
                    val id = try {
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
                    } catch (e: Exception) { "" }
                    result.success(id)
                }
                "deviceModel" -> result.success((Build.MANUFACTURER ?: "") + " " + (Build.MODEL ?: ""))
                "notify" -> {
                    val id = call.argument<Int>("id") ?: 1
                    val title = call.argument<String>("title") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    result.success(showNotification(id, title, body))
                }
                "btEnabled" -> {
                    try {
                        result.success(adapter()?.isEnabled == true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "btPaired" -> {
                    try {
                        result.success(paired())
                    } catch (e: SecurityException) {
                        result.error("PERMISSION", "Izin Bluetooth belum diberikan", null)
                    } catch (e: Exception) {
                        result.error("BT", e.message, null)
                    }
                }
                "btConnect" -> {
                    val addr = call.argument<String>("address") ?: ""
                    io.execute {
                        val ok = try { connect(addr) } catch (e: Exception) { false }
                        main.post { result.success(ok) }
                    }
                }
                "btIsConnected" -> {
                    val addr = call.argument<String>("address")
                    val s = socket
                    val ok = s != null && s.isConnected && (addr == null || addr == connectedAddress)
                    result.success(ok)
                }
                "btWrite" -> {
                    val data = call.argument<ByteArray>("data") ?: ByteArray(0)
                    val chunk = call.argument<Int>("chunk") ?: 256
                    val delay = (call.argument<Int>("delay") ?: 20).toLong()
                    io.execute {
                        val ok = write(data, chunk, delay)
                        main.post { result.success(ok) }
                    }
                }
                "btDisconnect" -> {
                    io.execute {
                        closeSocket()
                        main.post { result.success(true) }
                    }
                }
                "saveToDownloads" -> {
                    val src = call.argument<String>("path") ?: ""
                    val name = call.argument<String>("name") ?: "backup.db"
                    val folder = call.argument<String>("folder") ?: "AplikasiToko"
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    io.execute {
                        try {
                            val r = saveToDownloads(src, name, folder, mime)
                            main.post { result.success(r) }
                        } catch (e: Exception) {
                            main.post { result.error("SAVE", e.message, null) }
                        }
                    }
                }
                "openFile" -> {
                    // Simpan ke Download lalu buka langsung dengan aplikasi penampil (PDF/Excel)
                    val src = call.argument<String>("path") ?: ""
                    val name = call.argument<String>("name") ?: "file"
                    val folder = call.argument<String>("folder") ?: "AplikasiToko"
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    io.execute {
                        var uri: Uri? = null
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) uri = writeDownloadQ(src, name, folder, mime)
                        } catch (e: Exception) {
                            uri = null
                        }
                        main.post {
                            val u = uri
                            if (u == null) {
                                result.success(false)
                            } else {
                                try {
                                    val view = Intent(Intent.ACTION_VIEW).apply {
                                        setDataAndType(u, mime)
                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(view)
                                    result.success(true)
                                } catch (e: Exception) {
                                    result.success(false)
                                }
                            }
                        }
                    }
                }
                "pickFile" -> {
                    if (pendingPick != null) {
                        result.error("BUSY", "Pemilihan file sedang berjalan", null)
                    } else {
                        pendingPick = result
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        try {
                            startActivityForResult(i, pickCode)
                        } catch (e: Exception) {
                            pendingPick = null
                            result.error("PICK", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun paired(): List<Map<String, String>> {
        val ad = adapter() ?: return emptyList()
        if (!ad.isEnabled) return emptyList()
        val list = ArrayList<Map<String, String>>()
        for (d in ad.bondedDevices ?: emptySet<BluetoothDevice>()) {
            list.add(mapOf("name" to (d.name ?: "Tanpa Nama"), "address" to d.address))
        }
        return list
    }

    @SuppressLint("MissingPermission")
    private fun connect(address: String): Boolean {
        closeSocket()
        if (address.isEmpty()) return false
        val ad = adapter() ?: return false
        if (!ad.isEnabled) return false
        val dev: BluetoothDevice = try { ad.getRemoteDevice(address) } catch (e: Exception) { return false }
        try { ad.cancelDiscovery() } catch (_: Exception) { }

        // Beberapa cara koneksi agar cocok dengan berbagai merk printer thermal
        val makers: List<() -> BluetoothSocket?> = listOf(
            { dev.createRfcommSocketToServiceRecord(sppUuid) },
            { dev.createInsecureRfcommSocketToServiceRecord(sppUuid) },
            {
                val m = dev.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                m.invoke(dev, 1) as BluetoothSocket
            }
        )
        for (mk in makers) {
            var s: BluetoothSocket? = null
            try {
                s = mk()
                if (s != null) {
                    s.connect()
                    if (s.isConnected) {
                        socket = s
                        out = s.outputStream
                        connectedAddress = address
                        return true
                    }
                }
            } catch (e: Exception) {
                try { s?.close() } catch (_: Exception) { }
            }
        }
        return false
    }

    private fun write(data: ByteArray, chunk: Int, delay: Long): Boolean {
        val o = out ?: return false
        return try {
            val size = if (chunk <= 0) data.size.coerceAtLeast(1) else chunk
            var i = 0
            while (i < data.size) {
                val end = minOf(i + size, data.size)
                o.write(data, i, end - i)
                o.flush()
                i = end
                if (delay > 0 && i < data.size) Thread.sleep(delay)
            }
            true
        } catch (e: Exception) {
            closeSocket()
            false
        }
    }

    private fun closeSocket() {
        try { out?.close() } catch (_: Exception) { }
        try { socket?.close() } catch (_: Exception) { }
        out = null
        socket = null
        connectedAddress = null
    }

    /** Android 10+: tulis/timpa file di Download/<folder>/<name>, kembalikan Uri MediaStore */
    private fun writeDownloadQ(src: String, name: String, folder: String, mime: String): Uri? {
        val f = File(src)
        if (!f.exists()) return null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val resolver = contentResolver
        val rel = Environment.DIRECTORY_DOWNLOADS + "/" + folder + "/"
        val coll = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        var uri: Uri? = null
        resolver.query(
            coll,
            arrayOf(MediaStore.MediaColumns._ID),
            MediaStore.MediaColumns.DISPLAY_NAME + "=? AND " + MediaStore.MediaColumns.RELATIVE_PATH + "=?",
            arrayOf(name, rel),
            null
        )?.use { c ->
            if (c.moveToFirst()) uri = ContentUris.withAppendedId(coll, c.getLong(0))
        }
        if (uri == null) {
            val cv = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, rel)
            }
            uri = resolver.insert(coll, cv)
        }
        val u = uri ?: return null
        val os = resolver.openOutputStream(u, "wt") ?: return null
        os.use { o -> FileInputStream(f).use { it.copyTo(o) } }
        return u
    }

    private fun saveToDownloads(src: String, name: String, folder: String, mime: String): String? {
        val f = File(src)
        if (!f.exists()) return null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val rel = Environment.DIRECTORY_DOWNLOADS + "/" + folder + "/"
            val coll = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            var uri: Uri? = null
            resolver.query(
                coll,
                arrayOf(MediaStore.MediaColumns._ID),
                MediaStore.MediaColumns.DISPLAY_NAME + "=? AND " + MediaStore.MediaColumns.RELATIVE_PATH + "=?",
                arrayOf(name, rel),
                null
            )?.use { c ->
                if (c.moveToFirst()) uri = ContentUris.withAppendedId(coll, c.getLong(0))
            }
            if (uri == null) {
                val cv = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, rel)
                }
                uri = resolver.insert(coll, cv)
            }
            val u = uri ?: return null
            val os = resolver.openOutputStream(u, "wt") ?: return null
            os.use { o -> FileInputStream(f).use { it.copyTo(o) } }
            return rel + name
        } else {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), folder)
            if (!dir.exists()) dir.mkdirs()
            val dst = File(dir, name)
            f.copyTo(dst, overwrite = true)
            return dst.absolutePath
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickCode) return
        val r = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            r.success(null)
            return
        }
        io.execute {
            try {
                val dst = File(cacheDir, "picked_file.bin")
                val ins = contentResolver.openInputStream(uri)
                if (ins == null) {
                    main.post { r.error("PICK", "File tidak bisa dibuka", null) }
                } else {
                    ins.use { input -> dst.outputStream().use { input.copyTo(it) } }
                    main.post { r.success(dst.absolutePath) }
                }
            } catch (e: Exception) {
                main.post { r.error("PICK", e.message, null) }
            }
        }
    }

    private fun showNotification(id: Int, title: String, body: String): Boolean {
        return try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "stok_menipis"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val ch = NotificationChannel(channelId, "Stok Menipis", NotificationManager.IMPORTANCE_HIGH)
                ch.description = "Peringatan barang yang akan habis"
                nm.createNotificationChannel(ch)
            }
            val open = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
            val pi = PendingIntent.getActivity(this, 0, open, piFlags)
            val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, channelId)
            else Notification.Builder(this)
            b.setSmallIcon(R.drawable.ic_stat_notify)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(pi)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                b.setPriority(Notification.PRIORITY_HIGH)
                b.setDefaults(Notification.DEFAULT_ALL)
            }
            nm.notify(id, b.build())
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun onDestroy() {
        closeSocket()
        super.onDestroy()
    }
}
