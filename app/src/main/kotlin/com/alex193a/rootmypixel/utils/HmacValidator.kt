package com.alex193a.rootmypixel.utils

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object HmacValidator {
    private const val SECRET_KEY = "root-my-pixel-unroot-2026"
    private const val ALGORITHM = "HmacSHA256"

    fun validateHmac(content: String, expectedHmac: String): Boolean {
        val computedHmac = computeHmac(content)
        return computedHmac.equals(expectedHmac.trim(), ignoreCase = true)
    }

    fun computeHmac(content: String): String {
        val key = SecretKeySpec(SECRET_KEY.toByteArray(), 0, SECRET_KEY.length, ALGORITHM)
        val mac = Mac.getInstance(ALGORITHM)
        mac.init(key)
        val digest = mac.doFinal(content.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }
}
