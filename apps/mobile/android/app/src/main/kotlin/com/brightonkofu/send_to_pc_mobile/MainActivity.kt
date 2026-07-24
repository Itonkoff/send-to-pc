package com.brightonkofu.send_to_pc_mobile

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.InputStream
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.URL
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val pendingSharedFiles = mutableListOf<Map<String, Any?>>()
    private var shareChannel: MethodChannel? = null
    private val preferences by lazy {
        getSharedPreferences(PREFERENCES_NAME, MODE_PRIVATE)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationChannel()
        requestNotificationPermissionIfNeeded()
        captureIntent(intent)
        emitPendingFiles()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        shareChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getMobileSettings" -> result.success(loadMobileSettings())
                "saveMobileSettings" -> result.success(saveMobileSettings(call.arguments))
                "getInitialSharedFiles" -> result.success(pendingSharedFiles)
                "getPairedDevices" -> result.success(loadPairedDevices())
                "discoverPairedDevices" -> discoverPairedDevices(result)
                "getTransferHistory" -> result.success(loadTransferHistory())
                "clearTransferHistory" -> {
                    clearTransferHistory()
                    result.success(null)
                }
                "forgetPairedDevice" -> {
                    forgetPairedDevice(call.arguments)
                    result.success(loadPairedDevices())
                }
                "clearSharedFiles" -> {
                    pendingSharedFiles.clear()
                    result.success(null)
                }
                "pairWithComputer" -> pairWithComputer(call.arguments, result)
                "uploadSharedFiles" -> uploadSharedFiles(call.arguments, result)
                else -> result.notImplemented()
            }
        }
        emitPendingFiles()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIntent(intent)
        emitPendingFiles()
    }

    private fun pairWithComputer(arguments: Any?, result: MethodChannel.Result) {
        Thread {
            try {
                val args = arguments as? Map<*, *> ?: error("Missing pairing arguments.")
                val payloadText = args["pairingPayload"] as? String
                    ?: error("Missing pairing payload.")
                val phoneName = (args["deviceName"] as? String)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: defaultDeviceName()
                val payload = JSONObject(payloadText)
                val hostOverride = (args["hostOverride"] as? String)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                val requestedHost = hostOverride ?: payload.getString("host")
                val port = payload.getInt("port")
                val pairing = requestPairingWithReachableHost(
                    payload = payload,
                    requestedHost = requestedHost,
                    port = port,
                    phoneName = phoneName,
                    allowDiscoveryFallback = hostOverride == null,
                )
                val response = pairing.response
                val resolvedHost = pairing.host
                val now = utcNowIso()
                val receiverDeviceId = firstNotBlank(
                    optionalString(response, "receiverDeviceId"),
                    optionalString(payload, "deviceId"),
                    resolvedHost,
                )
                val receiverDeviceName = firstNotBlank(
                    optionalString(response, "receiverDeviceName"),
                    optionalString(payload, "deviceName"),
                    "Windows PC",
                )
                val certificateFingerprint = firstNotBlank(
                    optionalString(response, "certificateFingerprint"),
                    optionalString(payload, "certificateFingerprint"),
                    "development-http",
                )

                val device = mapOf(
                    "id" to receiverDeviceId,
                    "deviceId" to receiverDeviceId,
                    "deviceName" to receiverDeviceName,
                    "platform" to "windows",
                    "authenticationToken" to response.getString("deviceToken"),
                    "certificateFingerprint" to certificateFingerprint,
                    "lastKnownAddress" to resolvedHost,
                    "lastKnownPort" to port,
                    "lastSeenAt" to now,
                    "createdAt" to now,
                    "updatedAt" to now,
                    "isTrusted" to true,
                    "isRevoked" to false,
                )
                savePairedDevice(device)
                runOnUiThread { result.success(device) }
            } catch (exception: Exception) {
                runOnUiThread {
                    result.error(
                        "PAIRING_FAILED",
                        exception.message ?: "Pairing failed.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun requestPairing(
        payload: JSONObject,
        host: String,
        port: Int,
        phoneName: String,
    ): JSONObject {
        val connection = URL("http", host, port, "/api/v1/pairing/request")
            .openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = PAIRING_CONNECT_TIMEOUT_MS
        connection.readTimeout = 360_000
        connection.setRequestProperty("Content-Type", "application/json")
        connection.setRequestProperty("Accept", "application/json")
        connection.doOutput = true

        val body = JSONObject()
            .put("protocolVersion", payload.getInt("protocolVersion"))
            .put("pairingToken", payload.getString("pairingToken"))
            .put("deviceId", localDeviceId())
            .put("deviceName", phoneName)
            .put("platform", "android")
            .toString()

        connection.outputStream.use { output ->
            output.write(body.toByteArray(Charsets.UTF_8))
        }

        return JSONObject(readResponseOrThrow(connection, expectedCode = 200))
    }

    private fun requestPairingWithReachableHost(
        payload: JSONObject,
        requestedHost: String,
        port: Int,
        phoneName: String,
        allowDiscoveryFallback: Boolean,
    ): PairingAttempt {
        try {
            return PairingAttempt(
                response = requestPairing(payload, requestedHost, port, phoneName),
                host = requestedHost,
            )
        } catch (exception: Exception) {
            if (!allowDiscoveryFallback || !isConnectionFailure(exception)) {
                throw exception
            }

            for (host in pairingPayloadHosts(payload, requestedHost).drop(1)) {
                try {
                    return PairingAttempt(
                        response = requestPairing(payload, host, port, phoneName),
                        host = host,
                    )
                } catch (candidateException: Exception) {
                    if (!isConnectionFailure(candidateException)) {
                        throw candidateException
                    }
                }
            }

            val match = discoverPairingDevice(payload, requestedHost, port)
                ?: throw exception
            return PairingAttempt(
                response = requestPairing(payload, match.host, port, phoneName),
                host = match.host,
            )
        }
    }

    private fun pairingPayloadHosts(payload: JSONObject, requestedHost: String): List<String> {
        val hosts = linkedSetOf<String>()
        hosts.add(requestedHost)
        payload.optString("host")
            .trim()
            .takeIf { it.isNotEmpty() }
            ?.let { hosts.add(it) }

        val alternatives = payload.optJSONArray("hostAlternatives")
        if (alternatives != null) {
            for (index in 0 until alternatives.length()) {
                alternatives.optString(index)
                    .trim()
                    .takeIf { it.isNotEmpty() }
                    ?.let { hosts.add(it) }
            }
        }
        return hosts.toList()
    }

    private fun discoverPairingDevice(
        payload: JSONObject,
        requestedHost: String,
        port: Int,
    ): DiscoveryMatch? {
        val expectedDeviceId = payload.optString("deviceId")
            .trim()
            .takeIf { it.isNotEmpty() }
            ?: return null
        val device = mapOf<String, Any?>(
            "deviceId" to expectedDeviceId,
            "lastKnownAddress" to requestedHost,
            "lastKnownPort" to port,
        )
        return discoverDevice(device, pairingDiscoveryCandidates(requestedHost), port)
    }

    private fun isConnectionFailure(exception: Throwable): Boolean {
        var current: Throwable? = exception
        while (current != null) {
            when (current) {
                is ConnectException,
                is NoRouteToHostException,
                is SocketException,
                is SocketTimeoutException,
                is UnknownHostException -> return true
            }
            current = current.cause
        }

        val message = exception.message?.lowercase(Locale.US).orEmpty()
        return message.contains("failed to connect") ||
            message.contains("connection refused") ||
            message.contains("timed out") ||
            message.contains("timeout")
    }

    private fun discoverPairedDevices(result: MethodChannel.Result) {
        Thread {
            try {
                val now = utcNowIso()
                val updatedDevices = loadPairedDevices().map { device ->
                    val port = devicePort(device)
                    val match = discoverDevice(device, discoveryCandidates(device), port)
                    if (match == null) {
                        device
                    } else {
                        device.toMutableMap().apply {
                            put("deviceName", match.deviceName ?: device["deviceName"])
                            put("platform", match.platform ?: device["platform"])
                            put("lastKnownAddress", match.host)
                            put("lastKnownPort", match.port)
                            put("lastSeenAt", now)
                            put("updatedAt", now)
                        }
                    }
                }
                persistPairedDevices(updatedDevices)
                runOnUiThread { result.success(updatedDevices) }
            } catch (exception: Exception) {
                runOnUiThread {
                    result.error(
                        "DISCOVERY_FAILED",
                        exception.message ?: "Discovery failed.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun discoverDevice(
        device: Map<String, Any?>,
        candidates: List<String>,
        port: Int,
    ): DiscoveryMatch? {
        val expectedDeviceId = device["deviceId"] as? String ?: return null
        if (candidates.isEmpty()) {
            return null
        }

        val match = AtomicReference<DiscoveryMatch?>()
        val executor = Executors.newFixedThreadPool(DISCOVERY_CONCURRENCY)
        val latch = CountDownLatch(candidates.size)

        candidates.forEach { host ->
            executor.execute {
                try {
                    if (match.get() == null) {
                        val info = probeDevice(host, port)
                        if (info?.optString("deviceId") == expectedDeviceId) {
                            match.compareAndSet(
                                null,
                                DiscoveryMatch(
                                    host = host,
                                    port = port,
                                    deviceName = optionalString(info, "deviceName"),
                                    platform = optionalString(info, "platform"),
                                ),
                            )
                        }
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        latch.await(DISCOVERY_WAIT_SECONDS, TimeUnit.SECONDS)
        executor.shutdownNow()
        return match.get()
    }

    private fun probeDevice(host: String, port: Int): JSONObject? {
        var connection: HttpURLConnection? = null
        return try {
            connection = URL("http", host, port, "/api/v1/device")
                .openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = DISCOVERY_CONNECT_TIMEOUT_MS
            connection.readTimeout = DISCOVERY_READ_TIMEOUT_MS
            connection.setRequestProperty("Accept", "application/json")
            if (connection.responseCode == HttpURLConnection.HTTP_OK) {
                JSONObject(connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() })
            } else {
                null
            }
        } catch (ignored: Exception) {
            null
        } finally {
            connection?.disconnect()
        }
    }

    private fun pairingDiscoveryCandidates(requestedHost: String): List<String> {
        val hosts = linkedSetOf<String>()
        hosts.add(EMULATOR_HOST_ADDRESS)
        localIpv4Addresses().forEach { address ->
            hosts.add(address)
            hosts.addAll(ipv4SubnetCandidates(address))
        }
        hosts.add(requestedHost)
        hosts.addAll(ipv4SubnetCandidates(requestedHost))
        return hosts.toList()
    }

    private fun discoveryCandidates(device: Map<String, Any?>): List<String> {
        val hosts = linkedSetOf<String>()
        val savedHost = (device["lastKnownAddress"] as? String)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        if (savedHost != null) {
            hosts.add(savedHost)
            hosts.addAll(ipv4SubnetCandidates(savedHost))
        }

        hosts.add(EMULATOR_HOST_ADDRESS)
        localIpv4Addresses().forEach { address ->
            hosts.add(address)
            hosts.addAll(ipv4SubnetCandidates(address))
        }
        return hosts.toList()
    }

    private fun localIpv4Addresses(): List<String> {
        val addresses = mutableListOf<String>()
        return try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val networkInterface = interfaces.nextElement()
                if (!networkInterface.isUp || networkInterface.isLoopback) {
                    continue
                }
                val inetAddresses = networkInterface.inetAddresses
                while (inetAddresses.hasMoreElements()) {
                    val address = inetAddresses.nextElement()
                    if (address is Inet4Address &&
                        !address.isLoopbackAddress &&
                        !address.isLinkLocalAddress
                    ) {
                        addresses.add(address.hostAddress)
                    }
                }
            }
            addresses.distinct()
        } catch (ignored: Exception) {
            emptyList()
        }
    }

    private fun ipv4SubnetCandidates(host: String): List<String> {
        val octets = host.split(".").map { part -> part.toIntOrNull() ?: return emptyList() }
        if (octets.size != 4 || octets[0] == 0 || octets[0] >= 224) {
            return emptyList()
        }
        val prefix = "${octets[0]}.${octets[1]}.${octets[2]}."
        return (1..254).map { value -> "$prefix$value" }
    }

    private fun devicePort(device: Map<String, Any?>): Int {
        val port = (device["lastKnownPort"] as? Number)?.toInt()
        return port?.takeIf { it in 1..65535 } ?: DEFAULT_RECEIVER_PORT
    }

    private fun uploadSharedFiles(arguments: Any?, result: MethodChannel.Result) {
        Thread {
            var files = emptyList<SharedUploadFile>()
            var destination: UploadDestination? = null
            var failedStartIndex = 0
            try {
                val args = arguments as? Map<*, *> ?: error("Missing upload arguments.")
                val mobileSettings = loadMobileSettings()
                val wifiOnly = (args["wifiOnly"] as? Boolean)
                    ?: (mobileSettings["wifiOnly"] as? Boolean)
                    ?: false
                destination = UploadDestination(
                    host = args["host"] as? String ?: error("Missing host."),
                    port = (args["port"] as? Number)?.toInt() ?: error("Missing port."),
                    token = args["token"] as? String ?: error("Missing token."),
                )
                files = (args["files"] as? List<*>)
                    ?.mapNotNull { it as? Map<*, *> }
                    ?.map { SharedUploadFile.fromMap(it) }
                    ?: emptyList()

                if (files.isEmpty()) {
                    error("No files were provided for upload.")
                }

                if (wifiOnly && !isWifiConnected()) {
                    error("Wi-Fi only is enabled, but this device is not connected to Wi-Fi.")
                }

                val uploadDestination = destination ?: error("Missing destination.")
                files.forEachIndexed { index, file ->
                    failedStartIndex = index
                    uploadOneFile(uploadDestination, file, index + 1, files.size)
                    failedStartIndex = index + 1
                }

                runOnUiThread { result.success(null) }
            } catch (exception: Exception) {
                val failedFiles = files.drop(failedStartIndex)
                saveFailedTransferRecords(
                    failedFiles,
                    destination,
                    exception,
                )
                val failedFileName = failedFiles.firstOrNull()?.fileName
                    ?: files.firstOrNull()?.fileName
                showTransferNotification(
                    title = "Transfer failed",
                    text = failedFileName?.let { "$it could not be sent." }
                        ?: (exception.message ?: "Upload failed."),
                    failed = true,
                )
                runOnUiThread {
                    result.error(
                        "UPLOAD_FAILED",
                        exception.message ?: "Upload failed.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun uploadOneFile(
        destination: UploadDestination,
        file: SharedUploadFile,
        currentFileNumber: Int,
        totalFileCount: Int,
    ) {
        emitProgress(
            transferId = "pending",
            fileName = file.fileName,
            bytesTransferred = 0L,
            totalBytes = file.size ?: 0L,
            status = "connecting",
            currentFileNumber = currentFileNumber,
            totalFileCount = totalFileCount,
        )
        showTransferNotification(
            title = "Sending ${file.fileName}",
            text = "File $currentFileNumber of $totalFileCount is uploading.",
        )

        val checksum = calculateChecksum(file.uri)
        val transfer = createTransfer(destination, file, checksum)
        streamUpload(destination, file, checksum.size, transfer.transferId, currentFileNumber, totalFileCount)
        val completed = completeTransfer(destination, transfer.transferId)
        saveTransferRecord(jsonObjectToMap(completed))
        showTransferNotification(
            title = "Transfer complete",
            text = "${file.fileName} sent to PC.",
            completed = true,
        )

        emitProgress(
            transferId = transfer.transferId,
            fileName = file.fileName,
            bytesTransferred = checksum.size,
            totalBytes = checksum.size,
            status = "completed",
            currentFileNumber = currentFileNumber,
            totalFileCount = totalFileCount,
        )
    }

    private fun calculateChecksum(uri: Uri): ChecksumResult {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var totalBytes = 0L

        openSharedInputStream(uri).use { input ->
            while (true) {
                val read = input.read(buffer)
                if (read == -1) break
                digest.update(buffer, 0, read)
                totalBytes += read.toLong()
            }
        }

        return ChecksumResult(
            checksum = digest.digest().joinToString("") { byte ->
                "%02x".format(byte.toInt() and 0xff)
            },
            size = totalBytes,
        )
    }

    private fun createTransfer(
        destination: UploadDestination,
        file: SharedUploadFile,
        checksum: ChecksumResult,
    ): TransferCreateResult {
        val connection = openConnection(destination, "/api/v1/transfers", "POST")
        connection.setRequestProperty("Content-Type", "application/json")
        connection.doOutput = true

        val body = JSONObject()
            .put("fileName", file.fileName)
            .put("mimeType", file.mimeType)
            .put("fileSize", checksum.size)
            .put("checksumAlgorithm", "SHA-256")
            .put("checksum", checksum.checksum)
            .toString()

        connection.outputStream.use { output ->
            output.write(body.toByteArray(Charsets.UTF_8))
        }

        val response = readResponseOrThrow(connection, expectedCode = 201)
        val json = JSONObject(response)
        return TransferCreateResult(
            transferId = json.getString("transferId"),
            uploadUrl = json.getString("uploadUrl"),
        )
    }

    private fun streamUpload(
        destination: UploadDestination,
        file: SharedUploadFile,
        size: Long,
        transferId: String,
        currentFileNumber: Int,
        totalFileCount: Int,
    ) {
        val connection = openConnection(
            destination,
            "/api/v1/transfers/$transferId/content",
            "PUT",
        )
        connection.setRequestProperty("Content-Type", "application/octet-stream")
        connection.doOutput = true
        connection.setFixedLengthStreamingMode(size)

        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var transferred = 0L
        var lastProgress = 0L

        openSharedInputStream(file.uri).use { input ->
            BufferedOutputStream(connection.outputStream).use { output ->
                while (true) {
                    val read = input.read(buffer)
                    if (read == -1) break
                    output.write(buffer, 0, read)
                    transferred += read.toLong()

                    if (transferred - lastProgress >= 256L * 1024L || transferred == size) {
                        lastProgress = transferred
                        emitProgress(
                            transferId = transferId,
                            fileName = file.fileName,
                            bytesTransferred = transferred,
                            totalBytes = size,
                            status = "uploading",
                            currentFileNumber = currentFileNumber,
                            totalFileCount = totalFileCount,
                        )
                    }
                }
            }
        }

        readResponseOrThrow(connection, expectedCode = 200)
    }

    private fun completeTransfer(destination: UploadDestination, transferId: String): JSONObject {
        val connection = openConnection(
            destination,
            "/api/v1/transfers/$transferId/complete",
            "POST",
        )
        return JSONObject(readResponseOrThrow(connection, expectedCode = 200))
    }

    private fun openConnection(
        destination: UploadDestination,
        path: String,
        method: String,
    ): HttpURLConnection {
        val url = URL("http", destination.host, destination.port, path)
        val connection = url.openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.connectTimeout = 15_000
        connection.readTimeout = 120_000
        connection.setRequestProperty("Authorization", "Bearer ${destination.token}")
        connection.setRequestProperty("Accept", "application/json")
        return connection
    }

    private fun readResponseOrThrow(
        connection: HttpURLConnection,
        expectedCode: Int,
    ): String {
        val code = connection.responseCode
        val stream = if (code in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
        if (code != expectedCode) {
            error("HTTP $code: $body")
        }
        return body
    }

    private fun openSharedInputStream(uri: Uri): InputStream {
        return BufferedInputStream(
            contentResolver.openInputStream(uri) ?: error("Could not open shared file."),
        )
    }

    private fun captureIntent(intent: Intent?) {
        val files = extractSharedFiles(intent)
        if (files.isNotEmpty()) {
            pendingSharedFiles.clear()
            pendingSharedFiles.addAll(files)
        }
    }

    private fun emitPendingFiles() {
        shareChannel?.invokeMethod("sharedFilesUpdated", pendingSharedFiles)
    }

    private fun emitProgress(
        transferId: String,
        fileName: String,
        bytesTransferred: Long,
        totalBytes: Long,
        status: String,
        currentFileNumber: Int,
        totalFileCount: Int,
    ) {
        val event = mapOf(
            "transferId" to transferId,
            "fileName" to fileName,
            "bytesTransferred" to bytesTransferred,
            "totalBytes" to totalBytes,
            "status" to status,
            "currentFileNumber" to currentFileNumber,
            "totalFileCount" to totalFileCount,
        )
        runOnUiThread {
            shareChannel?.invokeMethod("transferProgressUpdated", event)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID)
        if (existing != null) {
            return
        }
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Transfers",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Send to PC transfer updates"
        }
        manager.createNotificationChannel(channel)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun showTransferNotification(
        title: String,
        text: String,
        completed: Boolean = false,
        failed: Boolean = false,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        ensureNotificationChannel()
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val icon = if (failed) {
            android.R.drawable.ic_dialog_alert
        } else {
            android.R.drawable.ic_dialog_info
        }
        builder
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(completed || failed)
            .setOnlyAlertOnce(!completed && !failed)

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(TRANSFER_NOTIFICATION_ID, builder.build())
    }

    private fun isWifiConnected(): Boolean {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = manager.activeNetwork ?: return false
            val capabilities = manager.getNetworkCapabilities(network) ?: return false
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
        } else {
            @Suppress("DEPRECATION")
            val info = manager.activeNetworkInfo
            @Suppress("DEPRECATION")
            info?.isConnected == true &&
                info.type == ConnectivityManager.TYPE_WIFI
        }
    }

    private fun extractSharedFiles(intent: Intent?): List<Map<String, Any?>> {
        if (intent == null) return emptyList()

        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> getStreamUri(intent)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> uris.addAll(getStreamUris(intent))
        }

        val clipData = intent.clipData
        if (uris.isEmpty() && clipData != null) {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let { uris.add(it) }
            }
        }

        return uris
            .distinct()
            .take(20)
            .mapIndexed { index, uri -> metadataFor(uri, intent.type, index) }
    }

    private fun getStreamUri(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            legacyStreamUri(intent)
        }
    }

    @Suppress("DEPRECATION")
    private fun legacyStreamUri(intent: Intent): Uri? {
        return intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
    }

    private fun getStreamUris(intent: Intent): List<Uri> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                ?.filterNotNull()
                ?: emptyList()
        } else {
            legacyStreamUris(intent)
        }
    }

    @Suppress("DEPRECATION")
    private fun legacyStreamUris(intent: Intent): List<Uri> {
        return intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            ?: emptyList()
    }

    private fun metadataFor(
        uri: Uri,
        fallbackMimeType: String?,
        index: Int,
    ): Map<String, Any?> {
        var displayName: String? = null
        var size: Long? = null

        try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameColumn >= 0) {
                        displayName = cursor.getString(nameColumn)
                    }
                    val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) {
                        size = cursor.getLong(sizeColumn)
                    }
                }
            }
        } catch (ignored: Exception) {
            displayName = null
            size = null
        }

        val fileName = displayName
            ?.takeIf { it.isNotBlank() }
            ?: uri.lastPathSegment?.substringAfterLast('/')
            ?: "shared-file-${index + 1}"
        val mimeType = contentResolver.getType(uri)
            ?: fallbackMimeType
            ?: "application/octet-stream"

        return mapOf(
            "id" to "${System.currentTimeMillis()}-$index-${uri.hashCode()}",
            "uri" to uri.toString(),
            "fileName" to fileName,
            "mimeType" to mimeType,
            "size" to size?.takeIf { it >= 0L },
        )
    }

    private fun loadPairedDevices(): List<Map<String, Any?>> {
        return loadJsonList(PAIRED_DEVICES_KEY)
    }

    private fun loadMobileSettings(): Map<String, Any?> {
        val defaults = defaultMobileSettings()
        val stored = preferences.getString(MOBILE_SETTINGS_KEY, null)
            ?: return defaults
        return try {
            normalizeMobileSettings(jsonObjectToMap(JSONObject(stored)))
        } catch (exception: Exception) {
            defaults
        }
    }

    private fun saveMobileSettings(arguments: Any?): Map<String, Any?> {
        val raw = arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val normalized = normalizeMobileSettings(raw.mapKeys { it.key.toString() })
        preferences.edit()
            .putString(MOBILE_SETTINGS_KEY, JSONObject(normalized).toString())
            .apply()
        persistTransferHistory(trimTransferHistory(loadJsonList(TRANSFER_HISTORY_KEY)))
        return normalized
    }

    private fun defaultMobileSettings(): Map<String, Any?> {
        return mapOf(
            "deviceName" to defaultDeviceName(),
            "defaultComputerId" to null,
            "confirmBeforeSending" to false,
            "wifiOnly" to false,
            "historyRetentionDays" to DEFAULT_HISTORY_RETENTION_DAYS,
        )
    }

    private fun normalizeMobileSettings(raw: Map<*, *>): Map<String, Any?> {
        val defaults = defaultMobileSettings()
        val deviceName = (raw["deviceName"] as? String)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: defaults["deviceName"] as String
        val defaultComputerId = (raw["defaultComputerId"] as? String)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        val retentionDays = ((raw["historyRetentionDays"] as? Number)?.toInt()
            ?: DEFAULT_HISTORY_RETENTION_DAYS)
            .coerceIn(1, 3650)
        return mapOf(
            "deviceName" to deviceName,
            "defaultComputerId" to defaultComputerId,
            "confirmBeforeSending" to (raw["confirmBeforeSending"] == true),
            "wifiOnly" to (raw["wifiOnly"] == true),
            "historyRetentionDays" to retentionDays,
        )
    }

    private fun loadTransferHistory(): List<Map<String, Any?>> {
        return trimTransferHistory(loadJsonList(TRANSFER_HISTORY_KEY))
    }

    private fun savePairedDevice(device: Map<String, Any?>) {
        val deviceId = device["deviceId"] as? String ?: return
        val devices = loadPairedDevices()
            .filterNot { existing ->
                existing["id"] == device["id"] || existing["deviceId"] == deviceId
            }
            .toMutableList()
        devices.add(0, device)
        persistPairedDevices(devices)
    }

    private fun forgetPairedDevice(arguments: Any?) {
        val args = arguments as? Map<*, *> ?: return
        val id = args["id"] as? String ?: return
        val devices = loadPairedDevices()
            .filterNot { device -> device["id"] == id || device["deviceId"] == id }
        persistPairedDevices(devices)
    }

    private fun persistPairedDevices(devices: List<Map<String, Any?>>) {
        persistJsonList(PAIRED_DEVICES_KEY, devices)
    }

    private fun saveFailedTransferRecords(
        files: List<SharedUploadFile>,
        destination: UploadDestination?,
        exception: Exception,
    ) {
        if (files.isEmpty()) {
            return
        }

        val now = utcNowIso()
        val message = exception.message ?: "Upload failed."
        files.forEachIndexed { index, file ->
            val size = file.size ?: 0L
            saveTransferRecord(
                mapOf(
                    "id" to "failed-${System.currentTimeMillis()}-$index-${file.uri.hashCode()}",
                    "senderDeviceId" to localDeviceId(),
                    "receiverDeviceId" to (destination?.host ?: "unknown"),
                    "fileName" to file.fileName,
                    "safeFileName" to file.fileName,
                    "mimeType" to file.mimeType,
                    "fileSize" to size,
                    "checksumAlgorithm" to "SHA-256",
                    "checksum" to "",
                    "status" to "failed",
                    "bytesTransferred" to 0L,
                    "failureCode" to "UPLOAD_FAILED",
                    "failureMessage" to message,
                    "createdAt" to now,
                    "completedAt" to now,
                    "updatedAt" to now,
                ),
            )
        }
    }

    private fun saveTransferRecord(record: Map<String, Any?>) {
        val recordId = record["id"] as? String ?: return
        val records = loadTransferHistory()
            .filterNot { existing -> existing["id"] == recordId }
            .toMutableList()
        records.add(0, record)
        persistTransferHistory(records.take(MAX_TRANSFER_HISTORY))
    }

    private fun clearTransferHistory() {
        persistTransferHistory(emptyList())
    }

    private fun persistTransferHistory(records: List<Map<String, Any?>>) {
        persistJsonList(TRANSFER_HISTORY_KEY, trimTransferHistory(records))
    }

    private fun trimTransferHistory(records: List<Map<String, Any?>>): List<Map<String, Any?>> {
        val retentionDays = (loadMobileSettings()["historyRetentionDays"] as? Number)?.toInt()
            ?: DEFAULT_HISTORY_RETENTION_DAYS
        val cutoff = System.currentTimeMillis() - TimeUnit.DAYS.toMillis(retentionDays.toLong())
        return records
            .filter { record ->
                val timestamp = parseUtcIsoMillis(
                    record["completedAt"] ?: record["updatedAt"] ?: record["createdAt"],
                )
                timestamp == null || timestamp >= cutoff
            }
            .take(MAX_TRANSFER_HISTORY)
    }

    private fun parseUtcIsoMillis(value: Any?): Long? {
        val text = value as? String ?: return null
        return try {
            val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            format.timeZone = TimeZone.getTimeZone("UTC")
            format.parse(text)?.time
        } catch (exception: Exception) {
            null
        }
    }

    private fun loadJsonList(key: String): List<Map<String, Any?>> {
        val stored = preferences.getString(key, "[]") ?: "[]"
        return try {
            val array = JSONArray(stored)
            val entries = mutableListOf<Map<String, Any?>>()
            for (index in 0 until array.length()) {
                val json = array.optJSONObject(index) ?: continue
                entries.add(jsonObjectToMap(json))
            }
            entries
        } catch (exception: Exception) {
            emptyList()
        }
    }

    private fun persistJsonList(key: String, entries: List<Map<String, Any?>>) {
        val array = JSONArray()
        entries.forEach { entry -> array.put(JSONObject(entry)) }
        preferences.edit().putString(key, array.toString()).apply()
    }

    private fun jsonObjectToMap(json: JSONObject): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = json.opt(key)
            result[key] = if (value == JSONObject.NULL) null else value
        }
        return result
    }

    private fun localDeviceId(): String {
        val existing = preferences.getString(LOCAL_DEVICE_ID_KEY, null)
        if (!existing.isNullOrBlank()) {
            return existing
        }
        val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        val generated = "android-${androidId ?: System.currentTimeMillis().toString(16)}"
        preferences.edit().putString(LOCAL_DEVICE_ID_KEY, generated).apply()
        return generated
    }

    private fun defaultDeviceName(): String {
        return listOf(Build.MANUFACTURER, Build.MODEL)
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .joinToString(" ")
            .ifBlank { "Android phone" }
    }

    private fun utcNowIso(): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date())
    }

    private fun optionalString(json: JSONObject, key: String): String? {
        return json.optString(key, "").takeIf { it.isNotBlank() }
    }

    private fun firstNotBlank(vararg values: String?): String {
        return values.firstOrNull { !it.isNullOrBlank() } ?: "unknown"
    }
}

private const val CHANNEL_NAME = "send_to_pc/share"
private const val PREFERENCES_NAME = "send_to_pc_mobile"
private const val PAIRED_DEVICES_KEY = "paired_devices_json"
private const val TRANSFER_HISTORY_KEY = "transfer_history_json"
private const val MOBILE_SETTINGS_KEY = "mobile_settings_json"
private const val LOCAL_DEVICE_ID_KEY = "local_device_id"
private const val MAX_TRANSFER_HISTORY = 50
private const val DEFAULT_HISTORY_RETENTION_DAYS = 30
private const val DEFAULT_BUFFER_SIZE = 64 * 1024
private const val DEFAULT_RECEIVER_PORT = 45873
private const val PAIRING_CONNECT_TIMEOUT_MS = 3_000
private const val EMULATOR_HOST_ADDRESS = "10.0.2.2"
private const val DISCOVERY_CONCURRENCY = 48
private const val DISCOVERY_CONNECT_TIMEOUT_MS = 450
private const val DISCOVERY_READ_TIMEOUT_MS = 450
private const val DISCOVERY_WAIT_SECONDS = 6L
private const val NOTIFICATION_CHANNEL_ID = "send_to_pc_transfers"
private const val TRANSFER_NOTIFICATION_ID = 45873
private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 45874

private data class PairingAttempt(
    val response: JSONObject,
    val host: String,
)

private data class DiscoveryMatch(
    val host: String,
    val port: Int,
    val deviceName: String?,
    val platform: String?,
)

private data class UploadDestination(
    val host: String,
    val port: Int,
    val token: String,
)

private data class SharedUploadFile(
    val uri: Uri,
    val fileName: String,
    val mimeType: String,
    val size: Long?,
) {
    companion object {
        fun fromMap(map: Map<*, *>): SharedUploadFile {
            return SharedUploadFile(
                uri = Uri.parse(map["uri"] as? String ?: error("Missing file URI.")),
                fileName = map["fileName"] as? String ?: "shared-file",
                mimeType = map["mimeType"] as? String ?: "application/octet-stream",
                size = (map["size"] as? Number)?.toLong(),
            )
        }
    }
}

private data class ChecksumResult(
    val checksum: String,
    val size: Long,
)

private data class TransferCreateResult(
    val transferId: String,
    val uploadUrl: String,
)
