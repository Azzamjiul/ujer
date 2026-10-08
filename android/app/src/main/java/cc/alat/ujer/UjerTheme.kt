package cc.alat.ujer

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Graphite = Color(0xFF111315)
private val Surface = Color(0xFF1B1F22)
private val Cobalt = Color(0xFF7B9CFF)
private val TextPrimary = Color(0xFFF4F6F6)
private val TextMuted = Color(0xFFAAB4B8)
private val Outline = Color(0xFF3C454A)

@Composable
fun UjerTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Cobalt,
            onPrimary = Color(0xFF0B1226),
            primaryContainer = Color(0xFF26396E),
            onPrimaryContainer = Color(0xFFDCE2FF),
            background = Graphite,
            onBackground = TextPrimary,
            surface = Surface,
            onSurface = TextPrimary,
            surfaceVariant = Outline,
            onSurfaceVariant = TextMuted,
            outline = Outline,
            outlineVariant = Color(0xFF59656A),
        ),
        content = content,
    )
}
