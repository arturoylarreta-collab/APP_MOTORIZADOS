package com.example.app_motorizados

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        crearCanalDeRastreo()
    }

    /**
     * El servicio de rastreo (flutter_background_service) muestra una notificación
     * permanente en el canal "vendu_location_channel". En Android 8+ ese canal
     * DEBE existir antes de arrancar el servicio; si no, Android lanza
     * "Bad notification for startForeground" y la app se cierra. Aquí se crea
     * (crear un canal que ya existe no hace nada).
     */
    private fun crearCanalDeRastreo() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val canal = NotificationChannel(
                "vendu_location_channel",
                "Rastreo de ruta",
                NotificationManager.IMPORTANCE_LOW
            )
            canal.description = "Se muestra mientras la app transmite la ubicación del motorizado"
            canal.setShowBadge(false)
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(canal)
        }
    }
}
