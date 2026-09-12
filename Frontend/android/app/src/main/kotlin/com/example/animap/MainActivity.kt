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

class MainActivity : FlutterActivity() {
    private val channelName = "animap/location"
    private val permissionRequestCode = 4201
    private val handler = Handler(Looper.getMainLooper())
    private var pendingResult: MethodChannel.Result? = null
    private var activeListener: LocationListener? = null
    private var timeout: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
        ).filter { provider ->
            runCatching { manager.isProviderEnabled(provider) }.getOrDefault(false)
        }

        if (providers.isEmpty()) {
            finishWithError("LOCATION_DISABLED", "Activa la ubicación del dispositivo")
            return
        }

        val lastLocation = providers
            .mapNotNull { provider ->
                runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
            }
            .maxByOrNull { location -> location.time }

        if (lastLocation != null) {
            finishWithLocation(lastLocation)
            return
        }

        val provider = if (providers.contains(LocationManager.GPS_PROVIDER)) {
            LocationManager.GPS_PROVIDER
        } else {
            providers.first()
        }
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                manager.removeUpdates(this)
                finishWithLocation(location)
            }

            override fun onProviderDisabled(disabledProvider: String) {
                if (disabledProvider == provider) {
                    manager.removeUpdates(this)
                    finishWithError(
                        "LOCATION_DISABLED",
                        "El proveedor de ubicación fue desactivado",
                    )
                }
            }

            override fun onProviderEnabled(enabledProvider: String) = Unit

            @Deprecated("Deprecated in Android")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
        }
        activeListener = listener
        try {
            manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
        } catch (_: SecurityException) {
            finishWithError("LOCATION_PERMISSION", "No hay permiso para usar la ubicación")
            return
        }

        timeout = Runnable {
            activeListener?.let { manager.removeUpdates(it) }
            finishWithError("LOCATION_TIMEOUT", "No se obtuvo una ubicación a tiempo")
        }.also { handler.postDelayed(it, 15000) }
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
}
