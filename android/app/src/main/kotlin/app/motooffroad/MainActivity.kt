package app.motooffroad

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var callBridge: CallBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bridge = CallBridge(this)
        callBridge = bridge

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CallBridge.METHOD_CHANNEL)
            .setMethodCallHandler { call, result -> bridge.handle(call, result) }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CallBridge.EVENT_CHANNEL)
            .setStreamHandler(bridge)
    }

    override fun onDestroy() {
        callBridge?.onCancel(null)
        callBridge = null
        super.onDestroy()
    }
}
