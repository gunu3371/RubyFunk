package io.github.gunu3371.rubyfunk

import android.os.Build
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// RubyFunk fallback for devices without Material You and deterministic previews.
internal val BrandDark = darkColorScheme(
    primary = Color(0xFFFF477B),
    onPrimary = Color(0xFF210E18),
    primaryContainer = Color(0xFF791331),
    onPrimaryContainer = Color(0xFFFFD9E4),
    secondary = Color(0xFFE8B8C8),
    onSecondary = Color(0xFF472331),
    tertiary = Color(0xFF8FD0E8),
    onTertiary = Color(0xFF053543),
    background = Color(0xFF180D13),
    onBackground = Color(0xFFF5E8EE),
    surface = Color(0xFF210E18),
    onSurface = Color(0xFFF5E8EE),
    surfaceVariant = Color(0xFF432530),
    onSurfaceVariant = Color(0xFFDCC1CC),
)

/** Follow Material You on supported devices; otherwise use the RubyFunk palette. */
@Composable
fun RubyFunkTheme(content: @Composable () -> Unit) {
    val scheme = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        dynamicDarkColorScheme(LocalContext.current)
    } else {
        BrandDark
    }
    // Geist Sans across the whole type scale — the brand typeface the website and the Apple client
    // already ship (see Type.kt).
    MaterialTheme(colorScheme = scheme, typography = RubyFunkTypography, content = content)
}

/** A pill: a badge, a chip. */
val PillShape = RoundedCornerShape(50)

/**
 * The area content keeps clear: the system bars UNION the display cutout. `systemBarsPadding()`
 * leaves out the cutout, which in landscape is a side inset with no bar behind it.
 */
@Composable
fun Modifier.safeArea(): Modifier =
    windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout))
