package com.playwithme.godot

import android.util.Log

internal object AndroidDebugLog {
    fun d(tag: String, message: String) {
        if (BuildConfig.DEBUG) {
            Log.d(tag, message)
        }
    }

    fun d(tag: String, message: String, throwable: Throwable) {
        if (BuildConfig.DEBUG) {
            Log.d(tag, message, throwable)
        }
    }
}
