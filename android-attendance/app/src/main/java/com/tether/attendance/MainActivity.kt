package com.tether.attendance

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.tether.attendance.presentation.attendance.AttendanceRoute
import com.tether.attendance.presentation.theme.TetherTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            TetherTheme {
                AttendanceRoute()
            }
        }
    }
}
