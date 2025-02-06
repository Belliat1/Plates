import ai.onnxruntime.*
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.example.plate_recognition"
    private var session: InferenceSession? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Configura el canal de comunicación con Flutter
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "processFrame" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")

                    if (bytes != null && width != null && height != null) {
                        try {
                            val plateNumber = processFrame(bytes, width, height)
                            result.success(plateNumber)
                        } catch (e: Exception) {
                            result.error("INFERENCE_ERROR", "Error during inference: ${e.message}", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "Invalid arguments provided", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Inicializa el modelo ONNX al iniciar la actividad
        try {
            val modelPath = filesDir.absolutePath + "/plate_detection.onnx"
            session = InferenceSession(modelPath)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        super.onDestroy()

        // Libera los recursos del modelo ONNX
        session?.close()
    }

    private fun processFrame(bytes: ByteArray, width: Int, height: Int): String {
        if (session == null) {
            throw IllegalStateException("ONNX model not initialized")
        }

        // Preprocesar los datos
        val inputTensor = preprocessFrame(bytes, width, height)

        // Ejecutar la inferencia
        val outputs = session!!.run(arrayOf(inputTensor))

        // Procesar los resultados
        val detections = outputs[0].value as Array<FloatArray>
        return detectionsToPlate(detections)
    }

    private fun preprocessFrame(bytes: ByteArray, width: Int, height: Int): OnnxTensor {
        // Convierte la imagen en un tensor adecuado para el modelo
        val inputData = FloatArray(bytes.size) { i -> bytes[i].toFloat() / 255.0f } // Normalización
        val shape = longArrayOf(1, 3, height.toLong(), width.toLong()) // Asume formato [Batch, Channels, Height, Width]
        return OnnxTensor.createTensor(session!!.environment, inputData, shape)
    }

    private fun detectionsToPlate(detections: Array<FloatArray>): String {
        // Procesa las detecciones para obtener el número de la placa (placeholder, debe ajustarse al modelo)
        return "Placa detectada: ABC123" // Aquí deberías implementar la lógica para extraer el texto real
    }
}
