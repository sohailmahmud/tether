package com.tether.attendance

import android.app.Application
import com.tether.attendance.di.AppContainer

class TetherAttendanceApp : Application() {
    val container: AppContainer by lazy { AppContainer(this) }
}
