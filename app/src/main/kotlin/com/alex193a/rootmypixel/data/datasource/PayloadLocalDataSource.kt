package com.alex193a.rootmypixel.data.datasource

import android.content.Context
import com.alex193a.rootmypixel.data.model.BundledProfileDto
import com.alex193a.rootmypixel.data.model.BundledProfilesFeed
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileOutputStream

/**
 * Local data source that reads bundled profiles and extracts payload
 * assets shipped inside the APK.
 */
open class PayloadLocalDataSource(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Read the bundled profiles.json from assets and return parsed profiles.
     */
    open fun loadProfiles(): Result<List<BundledProfileDto>> {
        return try {
            validateAssetPath(PROFILES_ASSET)
            val jsonString = context.assets.open(PROFILES_ASSET).bufferedReader().use { it.readText() }
            val feed = json.decodeFromString<BundledProfilesFeed>(jsonString)
            Result.success(feed.profiles)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Extract a file from APK assets to the app's files directory.
     * Returns the extracted file ready for execution.
     */
    open fun extractAsset(
        assetPath: String,
        destination: File,
        onProgress: (String) -> Unit,
    ): Result<File> {
        return try {
            require(destination.parentFile?.isDirectory == true) {
                "Destination directory is unavailable"
            }
            validateAssetPath(assetPath)
            onProgress("Extracting $assetPath...")
            val buffer = ByteArray(16384)

            context.assets.open(assetPath).use { input ->
                FileOutputStream(destination).use { output ->
                    var bytesRead: Int
                    var totalRead = 0L
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalRead += bytesRead
                    }
                }
            }

            onProgress("Extracted ${destination.name}")
            Result.success(destination)
        } catch (e: Exception) {
            destination.delete()
            Result.failure(e)
        }
    }

    private fun validateAssetPath(assetPath: String) {
        require(assetPath.isNotBlank()) {
            "Asset path cannot be empty"
        }
        require(!assetPath.startsWith("/")) {
            "Asset path must be relative (got: $assetPath)"
        }
        require(!assetPath.contains("..")) {
            "Asset path contains directory traversal attempt (got: $assetPath)"
        }
        require(!assetPath.contains("\\")) {
            "Asset path contains backslashes (got: $assetPath)"
        }
        require(assetPath.matches(Regex("""[a-zA-Z0-9._/\-]+"""))) {
            "Asset path contains invalid characters (got: $assetPath)"
        }
    }

    companion object {
        private const val PROFILES_ASSET = "profiles.json"
        const val KSUD_ASSET_PREFIX = "ksud/"
        const val EXPLOIT_ASSET_PREFIX = "exploits/"
    }
}
