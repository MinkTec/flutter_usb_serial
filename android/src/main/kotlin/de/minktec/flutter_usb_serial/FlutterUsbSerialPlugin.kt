package de.minktec.flutter_usb_serial

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.hoho.android.usbserial.driver.UsbSerialDriver
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import com.hoho.android.usbserial.util.SerialInputOutputManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

/** FlutterUsbSerialPlugin */
class FlutterUsbSerialPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var appContext: Context
    private lateinit var messenger: BinaryMessenger
    private var activity: Activity? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val portIdCounter = AtomicInteger(0)
    private val portMap = mutableMapOf<Int, PortEntry>()

    // Pending USB permission request (only one at a time)
    private var pendingPermissionResult: Result? = null
    private var pendingPermissionReceiver: BroadcastReceiver? = null

    // ── Hotplug device events ─────────────────────────────────────────────────

    private var devicesEventSink: EventChannel.EventSink? = null

    private val hotplugReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED,
                UsbManager.ACTION_USB_DEVICE_DETACHED -> emitDeviceSnapshot()
            }
        }
    }

    // ── Inner types ───────────────────────────────────────────────────────────

    private inner class PortEntry(
        val driver: UsbSerialDriver,
        val port: UsbSerialPort,
    ) {
        var ioManager: SerialInputOutputManager? = null
        var eventSink: EventChannel.EventSink? = null
        var eventChannel: EventChannel? = null
        val pendingData = ArrayDeque<ByteArray>()
    }

    companion object {
        private const val METHOD_CHANNEL = "flutter_usb_serial"
        private const val EVENT_CHANNEL_PREFIX = "flutter_usb_serial/read"
        private const val DEVICES_EVENT_CHANNEL = "flutter_usb_serial/devices"
        private const val ACTION_USB_PERMISSION = "de.minktec.flutter_usb_serial.USB_PERMISSION"
        private const val MAX_PENDING_BUFFERS = 50
    }

    // ── FlutterPlugin ─────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        messenger = binding.binaryMessenger
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        // Register persistent hotplug receiver
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(hotplugReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            appContext.registerReceiver(hotplugReceiver, filter)
        }

        // Set up the devices EventChannel
        val devicesChannel = EventChannel(messenger, DEVICES_EVENT_CHANNEL)
        devicesChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                devicesEventSink = events
                // Emit current snapshot immediately on subscribe
                emitDeviceSnapshot()
            }

            override fun onCancel(arguments: Any?) {
                devicesEventSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        portMap.values.forEach { closeEntry(it) }
        portMap.clear()
        try { appContext.unregisterReceiver(hotplugReceiver) } catch (_: Exception) {}
        devicesEventSink = null
    }

    // ── ActivityAware ─────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    // ── MethodCallHandler ─────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "getDevices"              -> getDevices(result)
                "hasPermission"           -> hasPermission(call, result)
                "requestPermission"       -> requestPermission(call, result)
                "openPort"                -> openPort(call, result)
                "closePort"               -> closePort(call, result)
                "write"                   -> write(call, result)
                "setParameters"           -> setParameters(call, result)
                "setRTS"                  -> setRTS(call, result)
                "setDTR"                  -> setDTR(call, result)
                "getControlLines"         -> getControlLines(call, result)
                "getSupportedControlLines" -> getSupportedControlLines(call, result)
                "setFlowControl"          -> setFlowControl(call, result)
                "purgeHwBuffers"          -> purgeHwBuffers(call, result)
                "setBreak"                -> setBreak(call, result)
                "isOpen"                  -> isOpen(call, result)
                else                      -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("PLUGIN_ERROR", e.message, e.toString())
        }
    }

    // ── Device enumeration ────────────────────────────────────────────────────

    private fun getDevices(result: Result) {
        val prober = UsbSerialProber.getDefaultProber()
        val usbManager = usbManager()
        val list = mutableListOf<Map<String, Any?>>()

        for (device in usbManager.deviceList.values) {
            val driver = prober.probeDevice(device) ?: continue
            val serialNumber = safeSerialNumber(device)
            list.add(
                mapOf(
                    "deviceId"        to device.deviceId,
                    "deviceName"      to device.deviceName,
                    "vendorId"        to device.vendorId,
                    "productId"       to device.productId,
                    "manufacturerName" to device.manufacturerName,
                    "productName"     to device.productName,
                    "serialNumber"    to serialNumber,
                    "driverType"      to driverTypeName(driver),
                    "portCount"       to driver.ports.size,
                    "hasPermission"   to usbManager.hasPermission(device),
                )
            )
        }
        result.success(list)
    }

    // ── Permissions ───────────────────────────────────────────────────────────

    private fun hasPermission(call: MethodCall, result: Result) {
        val device = requireDevice(call, result) ?: return
        result.success(usbManager().hasPermission(device))
    }

    private fun requestPermission(call: MethodCall, result: Result) {
        val device = requireDevice(call, result) ?: return

        if (usbManager().hasPermission(device)) {
            result.success(true)
            return
        }

        // Only one pending request at a time
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_BUSY", "Another permission request is already pending", null)
            return
        }

        val ctx: Context = activity ?: appContext
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_MUTABLE else 0
        val intent = Intent(ACTION_USB_PERMISSION).apply { setPackage(ctx.packageName) }
        val pi = PendingIntent.getBroadcast(ctx, 0, intent, flags)

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                try { ctx.unregisterReceiver(this) } catch (_: Exception) {}
                pendingPermissionReceiver = null
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                pendingPermissionResult?.success(granted)
                pendingPermissionResult = null
            }
        }
        pendingPermissionResult = result
        pendingPermissionReceiver = receiver

        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ctx.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            ctx.registerReceiver(receiver, filter)
        }
        usbManager().requestPermission(device, pi)
    }

    // ── Port lifecycle ────────────────────────────────────────────────────────

    private fun openPort(call: MethodCall, result: Result) {
        val deviceId  = call.argument<Int>("deviceId")  ?: return result.error("BAD_ARGS", "deviceId required", null)
        val portNumber = call.argument<Int>("portNumber") ?: 0
        val baudRate  = call.argument<Int>("baudRate")  ?: 9600
        val dataBits  = call.argument<Int>("dataBits")  ?: UsbSerialPort.DATABITS_8
        val stopBits  = call.argument<Int>("stopBits")  ?: UsbSerialPort.STOPBITS_1
        val parity    = call.argument<Int>("parity")    ?: UsbSerialPort.PARITY_NONE

        val usbMgr = usbManager()
        val device = usbMgr.deviceList.values.firstOrNull { it.deviceId == deviceId }
            ?: return result.error("DEVICE_NOT_FOUND", "Device $deviceId not found", null)

        if (!usbMgr.hasPermission(device)) {
            return result.error("NO_PERMISSION", "No USB permission for device $deviceId — call requestPermission first", null)
        }

        val driver = UsbSerialProber.getDefaultProber().probeDevice(device)
            ?: return result.error("NO_DRIVER", "No serial driver found for device $deviceId", null)

        if (portNumber >= driver.ports.size) {
            return result.error("INVALID_PORT", "Port $portNumber not found (device has ${driver.ports.size} port(s))", null)
        }

        val connection = usbMgr.openDevice(device)
            ?: return result.error("OPEN_FAILED", "Failed to open UsbDeviceConnection — permission may have been revoked", null)

        val port = driver.ports[portNumber]
        try {
            port.open(connection)
            port.setParameters(baudRate, dataBits, stopBits, parity)
        } catch (e: IOException) {
            try { connection.close() } catch (_: Exception) {}
            return result.error("OPEN_FAILED", e.message, null)
        }

        val portId = portIdCounter.getAndIncrement()
        val entry = PortEntry(driver, port)
        portMap[portId] = entry

        // Create a per-port EventChannel for streaming received bytes to Dart
        val channelName = "$EVENT_CHANNEL_PREFIX/$portId"
        val eventChannel = EventChannel(messenger, channelName)
        entry.eventChannel = eventChannel
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                entry.eventSink = events
                // Flush any data buffered before Dart subscribed
                entry.pendingData.forEach { events.success(it) }
                entry.pendingData.clear()
            }

            override fun onCancel(arguments: Any?) {
                entry.eventSink = null
            }
        })

        // Start the async read loop
        val ioManager = SerialInputOutputManager(port, object : SerialInputOutputManager.Listener {
            override fun onNewData(data: ByteArray) {
                mainHandler.post {
                    val sink = entry.eventSink
                    if (sink != null) {
                        sink.success(data)
                    } else {
                        if (entry.pendingData.size >= MAX_PENDING_BUFFERS) {
                            entry.pendingData.removeFirst()
                        }
                        entry.pendingData.addLast(data)
                    }
                }
            }

            override fun onRunError(e: Exception) {
                mainHandler.post {
                    entry.eventSink?.endOfStream()
                    entry.eventSink = null
                    portMap.remove(portId)
                }
            }
        })
        ioManager.start()
        entry.ioManager = ioManager

        result.success(portId)
    }

    private fun closePort(call: MethodCall, result: Result) {
        val portId = call.argument<Int>("portId") ?: return result.error("BAD_ARGS", "portId required", null)
        val entry = portMap.remove(portId) ?: return result.error("PORT_NOT_FOUND", "Port $portId is not open", null)
        closeEntry(entry)
        result.success(null)
    }

    private fun isOpen(call: MethodCall, result: Result) {
        val portId = call.argument<Int>("portId") ?: return result.error("BAD_ARGS", "portId required", null)
        result.success(portMap[portId]?.port?.isOpen == true)
    }

    // ── Data I/O ──────────────────────────────────────────────────────────────

    private fun write(call: MethodCall, result: Result) {
        val entry = requirePort(call, result) ?: return
        val data  = call.argument<ByteArray>("data") ?: return result.error("BAD_ARGS", "data required", null)
        try {
            entry.port.write(data, 2000)
            result.success(null)
        } catch (e: IOException) {
            result.error("WRITE_FAILED", e.message, null)
        }
    }

    // ── Port configuration ────────────────────────────────────────────────────

    private fun setParameters(call: MethodCall, result: Result) {
        val entry    = requirePort(call, result) ?: return
        val baudRate = call.argument<Int>("baudRate") ?: 9600
        val dataBits = call.argument<Int>("dataBits") ?: UsbSerialPort.DATABITS_8
        val stopBits = call.argument<Int>("stopBits") ?: UsbSerialPort.STOPBITS_1
        val parity   = call.argument<Int>("parity")   ?: UsbSerialPort.PARITY_NONE
        try {
            entry.port.setParameters(baudRate, dataBits, stopBits, parity)
            result.success(null)
        } catch (e: IOException) {
            result.error("SET_PARAMS_FAILED", e.message, null)
        }
    }

    private fun setFlowControl(call: MethodCall, result: Result) {
        val entry = requirePort(call, result) ?: return
        val mode  = call.argument<String>("mode") ?: return result.error("BAD_ARGS", "mode required", null)
        val fc = when (mode) {
            "RTS_CTS"         -> UsbSerialPort.FlowControl.RTS_CTS
            "DTR_DSR"         -> UsbSerialPort.FlowControl.DTR_DSR
            "XON_XOFF"        -> UsbSerialPort.FlowControl.XON_XOFF
            "XON_XOFF_INLINE" -> UsbSerialPort.FlowControl.XON_XOFF_INLINE
            else              -> UsbSerialPort.FlowControl.NONE
        }
        try {
            entry.port.setFlowControl(fc)
            result.success(null)
        } catch (e: IOException) {
            result.error("FLOW_CTRL_FAILED", e.message, null)
        } catch (e: UnsupportedOperationException) {
            result.error("UNSUPPORTED", "Flow control '$mode' not supported by this driver", null)
        }
    }

    private fun purgeHwBuffers(call: MethodCall, result: Result) {
        val entry      = requirePort(call, result) ?: return
        val purgeWrite = call.argument<Boolean>("purgeWrite") ?: true
        val purgeRead  = call.argument<Boolean>("purgeRead")  ?: true
        try {
            entry.port.purgeHwBuffers(purgeWrite, purgeRead)
            result.success(null)
        } catch (e: IOException) {
            result.error("PURGE_FAILED", e.message, null)
        } catch (e: UnsupportedOperationException) {
            result.error("UNSUPPORTED", "purgeHwBuffers not supported by this driver", null)
        }
    }

    private fun setBreak(call: MethodCall, result: Result) {
        val entry = requirePort(call, result) ?: return
        val value = call.argument<Boolean>("value") ?: false
        try {
            entry.port.setBreak(value)
            result.success(null)
        } catch (e: IOException) {
            result.error("BREAK_FAILED", e.message, null)
        } catch (e: UnsupportedOperationException) {
            result.error("UNSUPPORTED", "setBreak not supported by this driver", null)
        }
    }

    // ── Control lines ─────────────────────────────────────────────────────────

    private fun setRTS(call: MethodCall, result: Result) {
        val entry = requirePort(call, result) ?: return
        val value = call.argument<Boolean>("value") ?: false
        try {
            entry.port.setRTS(value)
            result.success(null)
        } catch (e: IOException) {
            result.error("CONTROL_LINE_FAILED", e.message, null)
        } catch (e: UnsupportedOperationException) {
            result.error("UNSUPPORTED", "RTS not supported by this driver", null)
        }
    }

    private fun setDTR(call: MethodCall, result: Result) {
        val entry = requirePort(call, result) ?: return
        val value = call.argument<Boolean>("value") ?: false
        try {
            entry.port.setDTR(value)
            result.success(null)
        } catch (e: IOException) {
            result.error("CONTROL_LINE_FAILED", e.message, null)
        } catch (e: UnsupportedOperationException) {
            result.error("UNSUPPORTED", "DTR not supported by this driver", null)
        }
    }

    private fun getControlLines(call: MethodCall, result: Result) {
        val entry = requirePort(call, result) ?: return
        try {
            val lines = entry.port.getControlLines()
            result.success(
                mapOf(
                    "RTS" to lines.contains(UsbSerialPort.ControlLine.RTS),
                    "CTS" to lines.contains(UsbSerialPort.ControlLine.CTS),
                    "DTR" to lines.contains(UsbSerialPort.ControlLine.DTR),
                    "DSR" to lines.contains(UsbSerialPort.ControlLine.DSR),
                    "CD"  to lines.contains(UsbSerialPort.ControlLine.CD),
                    "RI"  to lines.contains(UsbSerialPort.ControlLine.RI),
                )
            )
        } catch (e: IOException) {
            result.error("CONTROL_LINE_FAILED", e.message, null)
        } catch (e: UnsupportedOperationException) {
            // Driver doesn't support reading control lines; return all false
            result.success(mapOf("RTS" to false, "CTS" to false, "DTR" to false,
                "DSR" to false, "CD" to false, "RI" to false))
        }
    }

    private fun getSupportedControlLines(call: MethodCall, result: Result) {
        val entry = requirePort(call, result) ?: return
        try {
            val supported = entry.port.getSupportedControlLines()
            result.success(supported.map { it.name })
        } catch (e: IOException) {
            result.error("CONTROL_LINE_FAILED", e.message, null)
        } catch (e: UnsupportedOperationException) {
            result.success(emptyList<String>())
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun emitDeviceSnapshot() {
        val sink = devicesEventSink ?: return
        val prober = UsbSerialProber.getDefaultProber()
        val usbMgr = usbManager()
        val list = mutableListOf<Map<String, Any?>>()
        for (device in usbMgr.deviceList.values) {
            val driver = prober.probeDevice(device) ?: continue
            list.add(
                mapOf(
                    "deviceId"         to device.deviceId,
                    "deviceName"       to device.deviceName,
                    "vendorId"         to device.vendorId,
                    "productId"        to device.productId,
                    "manufacturerName" to device.manufacturerName,
                    "productName"      to device.productName,
                    "serialNumber"     to safeSerialNumber(device),
                    "driverType"       to driverTypeName(driver),
                    "portCount"        to driver.ports.size,
                    "hasPermission"    to usbMgr.hasPermission(device),
                )
            )
        }
        mainHandler.post { sink.success(list) }
    }

    private fun usbManager(): UsbManager =
        appContext.getSystemService(Context.USB_SERVICE) as UsbManager

    private fun requireDevice(call: MethodCall, result: Result): UsbDevice? {
        val deviceId = call.argument<Int>("deviceId")
            ?: run { result.error("BAD_ARGS", "deviceId required", null); return null }
        return usbManager().deviceList.values.firstOrNull { it.deviceId == deviceId }
            ?: run { result.error("DEVICE_NOT_FOUND", "Device $deviceId not found", null); null }
    }

    private fun requirePort(call: MethodCall, result: Result): PortEntry? {
        val portId = call.argument<Int>("portId")
            ?: run { result.error("BAD_ARGS", "portId required", null); return null }
        return portMap[portId]
            ?: run { result.error("PORT_NOT_FOUND", "Port $portId is not open", null); null }
    }

    private fun closeEntry(entry: PortEntry) {
        entry.ioManager?.stop()
        entry.eventSink?.endOfStream()
        entry.eventChannel?.setStreamHandler(null)
        try { entry.port.close() } catch (_: IOException) {}
    }

    private fun driverTypeName(driver: UsbSerialDriver): String =
        driver.javaClass.simpleName.removeSuffix("SerialDriver")

    private fun safeSerialNumber(device: UsbDevice): String? {
        return try {
            device.serialNumber
        } catch (_: SecurityException) {
            null
        }
    }
}
