package com.example.animap

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.SystemClock
import android.view.KeyEvent
import android.widget.Toast

class MainActivity : FlutterActivity() {
    private val channelName = "animap/location"
    private val permissionRequestCode = 4201
    private val handler = Handler(Looper.getMainLooper())
    private var pendingResult: MethodChannel.Result? = null
    private var activeListener: LocationListener? = null
    private var timeout: Runnable? = null

    // Configuración del atajo de emergencia AniMap.
    private val tiempoMaximoAtajo = 2000L
    private var primeraPulsacion = 0L
    private var contadorPulsaciones = 0

    private val shortcutChannelName = "animap/emergency_shortcut"
    private var shortcutChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shortcutChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            shortcutChannelName
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            if (call.method == "getCurrentLocation") {
                requestCurrentLocation(result)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun requestCurrentLocation(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("LOCATION_BUSY", "Ya hay una solicitud de ubicación en curso", null)
            return
        }

        pendingResult = result
        val fineGranted = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val coarseGranted = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (!fineGranted && !coarseGranted) {
            requestPermissions(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
                permissionRequestCode,
            )
            return
        }
        readLocation()
    }


    private fun readLocation() {
        val manager =
            getSystemService(Context.LOCATION_SERVICE) as LocationManager

        val fineGranted =
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED

        val coarseGranted =
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED

        if (!fineGranted && !coarseGranted) {
            finishWithError(
                "LOCATION_PERMISSION",
                "AniMap necesita permiso para obtener tu ubicación"
            )
            return
        }

        // Consultar los proveedores disponibles.
        // La red puede responder más rápido que el GPS.
        val providers = listOf(
            LocationManager.NETWORK_PROVIDER,
            LocationManager.GPS_PROVIDER
        ).filter { provider ->
            val permitted =
                provider != LocationManager.GPS_PROVIDER || fineGranted

            permitted && runCatching {
                manager.isProviderEnabled(provider)
            }.getOrDefault(false)
        }

        if (providers.isEmpty()) {
            finishWithError(
                "LOCATION_DISABLED",
                "Activa la ubicación del celular para continuar"
            )
            return
        }

        // La primera lectura nueva que llegue será utilizada.
        val listener = object : LocationListener {

            override fun onLocationChanged(location: Location) {
                if (pendingResult == null) return

                manager.removeUpdates(this)
                finishWithLocation(location)
            }

            override fun onProviderDisabled(provider: String) = Unit

            override fun onProviderEnabled(provider: String) = Unit

            @Deprecated("Deprecated in Android")
            override fun onStatusChanged(
                provider: String?,
                status: Int,
                extras: Bundle?
            ) = Unit
        }

        activeListener = listener

        var solicitudesIniciadas = 0

        for (provider in providers) {
            try {
                manager.requestSingleUpdate(
                    provider,
                    listener,
                    Looper.getMainLooper()
                )

                solicitudesIniciadas++
            } catch (_: SecurityException) {
                // Intentar con el siguiente proveedor.
            } catch (_: IllegalArgumentException) {
                // Proveedor no disponible en este dispositivo.
            }
        }

        if (solicitudesIniciadas == 0) {
            activeListener = null
            finishWithError(
                "LOCATION_UNAVAILABLE",
                "No fue posible iniciar la búsqueda de ubicación"
            )
            return
        }

        // Tiempo máximo para obtener una ubicación nueva.
        timeout = Runnable {
            manager.removeUpdates(listener)

            if (pendingResult != null) {
                finishWithError(
                    "LOCATION_TIMEOUT",
                    "No pudimos obtener tu ubicación actual. " +
                            "Puedes seleccionar el lugar manualmente."
                )
            }
        }.also {
            handler.postDelayed(it, 20000L)
        }
    }


    private fun finishWithLocation(location: Location) {
        clearLocationRequest()
        pendingResult?.success(
            mapOf(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "accuracy" to location.accuracy.toDouble(),
            ),
        )
        pendingResult = null
    }

    private fun finishWithError(code: String, message: String) {
        clearLocationRequest()
        pendingResult?.error(code, message, null)
        pendingResult = null
    }

    private fun clearLocationRequest() {
        timeout?.let { handler.removeCallbacks(it) }
        timeout = null
        activeListener = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        if (grantResults.any { result -> result == PackageManager.PERMISSION_GRANTED }) {
            readLocation()
        } else {
            finishWithError("LOCATION_PERMISSION", "Permiso de ubicación denegado")
        }
    }

    override fun onKeyDown(
        keyCode: Int,
        event: KeyEvent
    ): Boolean {

        // Detectar únicamente pulsaciones nuevas del botón
        // de subir volumen, evitando las repeticiones por
        // mantenerlo presionado.
        if (
            keyCode == KeyEvent.KEYCODE_VOLUME_UP &&
            event.repeatCount == 0
        ) {
            val ahora = SystemClock.elapsedRealtime()

            // Iniciar una nueva secuencia si se superaron
            // los dos segundos disponibles.
            if (
                contadorPulsaciones == 0 ||
                ahora - primeraPulsacion > tiempoMaximoAtajo
            ) {
                primeraPulsacion = ahora
                contadorPulsaciones = 1
            } else {
                contadorPulsaciones++
            }

            // Tres pulsaciones dentro de dos segundos.
            if (contadorPulsaciones >= 3) {
                contadorPulsaciones = 0
                primeraPulsacion = 0L

                Toast.makeText(
                    this,
                    "AniMap: atajo de reporte detectado",
                    Toast.LENGTH_LONG
                ).show()
                shortcutChannel?.invokeMethod(
                    "emergencyShortcutActivated",
                    null
                )
            }
        }

        // Mantener el comportamiento normal del volumen.
        return super.onKeyDown(keyCode, event)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shortcutChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

}
