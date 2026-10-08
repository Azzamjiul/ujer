package cc.alat.ujer

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val store = SettingsStore(this)
        setContent { SettingsScreen(store) }
    }
}

@Composable
private fun SettingsScreen(store: SettingsStore) {
    val context = LocalContext.current
    val saved = remember { store.settings() }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var provider by remember { mutableStateOf(saved.provider) }
    var baseUrl by remember { mutableStateOf(saved.baseUrl) }
    var model by remember { mutableStateOf(saved.model) }
    var token by remember { mutableStateOf(store.token(saved.provider).orEmpty()) }
    var tokenVisible by remember { mutableStateOf(false) }

    UjerTheme {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            bottomBar = {
                Surface(
                    color = MaterialTheme.colorScheme.background,
                    tonalElevation = 3.dp,
                ) {
                    Button(
                        onClick = {
                            try {
                                val settings = ProviderSettings(provider, baseUrl, model)
                                EndpointConfiguration(settings.baseUrl, settings.model)
                                store.save(settings, token)
                                scope.launch {
                                    snackbarHostState.showSnackbar("Settings saved", duration = SnackbarDuration.Short)
                                }
                            } catch (_: Exception) {
                                scope.launch {
                                    snackbarHostState.showSnackbar(
                                        "Check the Base URL and model. Use HTTPS except for localhost.",
                                        duration = SnackbarDuration.Short,
                                    )
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 12.dp)
                            .navigationBarsPadding(),
                    ) {
                        Text("SAVE SETTINGS")
                    }
                }
            },
        ) { contentPadding ->
            Surface(
                modifier = Modifier.fillMaxSize(),
                color = MaterialTheme.colorScheme.background,
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .imePadding()
                        .padding(contentPadding)
                        .padding(horizontal = 20.dp, vertical = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            "UJER",
                            style = MaterialTheme.typography.displaySmall,
                            color = MaterialTheme.colorScheme.onBackground,
                        )
                        Text(
                            "DICTATION SETUP",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Spacer(Modifier.size(4.dp))
                        Text(
                            "Configure your provider once, then dictate from Quick Settings.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    OutlinedCard(
                        colors = CardDefaults.outlinedCardColors(
                            containerColor = MaterialTheme.colorScheme.surface,
                        ),
                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text("Get started", style = MaterialTheme.typography.titleMedium)
                            Text(
                                "1. Save your provider details below.\n" +
                                    "2. Add Ujer from the Quick Settings edit menu.\n" +
                                    "3. Open a text field, tap the Ujer tile, then paste from your keyboard's clipboard panel.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("Provider", style = MaterialTheme.typography.titleMedium)
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Provider.entries.forEach { choice ->
                                FilterChip(
                                    selected = provider == choice,
                                    onClick = {
                                        provider = choice
                                        val config = store.settings(choice)
                                        baseUrl = config.baseUrl
                                        model = config.model
                                        token = store.token(choice).orEmpty()
                                        tokenVisible = false
                                    },
                                    label = { Text(choice.title) },
                                    colors = FilterChipDefaults.filterChipColors(
                                        selectedContainerColor = MaterialTheme.colorScheme.primary,
                                        selectedLabelColor = MaterialTheme.colorScheme.onPrimary,
                                    ),
                                )
                            }
                        }
                    }

                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("Connection", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Use the endpoint and model supplied by your provider.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        OutlinedCard(
                            colors = CardDefaults.outlinedCardColors(
                                containerColor = MaterialTheme.colorScheme.surface,
                            ),
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                        ) {
                            Column(
                                modifier = Modifier.padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                UjerTextField(
                                    value = baseUrl,
                                    onValueChange = { baseUrl = it },
                                    label = "Base URL",
                                )
                                UjerTextField(
                                    value = model,
                                    onValueChange = { model = it },
                                    label = "Model",
                                )
                                UjerTextField(
                                    value = token,
                                    onValueChange = { token = it },
                                    label = "API token",
                                    keyboardType = KeyboardType.Password,
                                    visualTransformation = if (tokenVisible) {
                                        VisualTransformation.None
                                    } else {
                                        PasswordVisualTransformation()
                                    },
                                    trailingContent = {
                                        Row {
                                            TextButton(
                                                onClick = { tokenVisible = !tokenVisible },
                                                contentPadding = PaddingValues(horizontal = 8.dp),
                                            ) {
                                                Text(if (tokenVisible) "HIDE" else "SHOW")
                                            }
                                            TextButton(
                                                onClick = {
                                                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                                    clipboard.setPrimaryClip(ClipData.newPlainText("Ujer API token", token))
                                                    scope.launch {
                                                        snackbarHostState.showSnackbar("API token copied", duration = SnackbarDuration.Short)
                                                    }
                                                },
                                                enabled = token.isNotBlank(),
                                                contentPadding = PaddingValues(horizontal = 8.dp),
                                            ) {
                                                Text("COPY")
                                            }
                                        }
                                    },
                                )
                                Text(
                                    "Stored securely on this device. The token is hidden by default.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun UjerTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    keyboardType: KeyboardType = KeyboardType.Text,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    trailingContent: (@Composable () -> Unit)? = null,
) {
    val bringIntoViewRequester = remember { BringIntoViewRequester() }
    val scope = rememberCoroutineScope()

    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier
            .fillMaxWidth()
            .bringIntoViewRequester(bringIntoViewRequester)
            .onFocusChanged { focusState ->
                if (focusState.isFocused) {
                    scope.launch {
                        delay(300)
                        bringIntoViewRequester.bringIntoView()
                    }
                }
            },
        label = { Text(label) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        visualTransformation = visualTransformation,
        trailingIcon = trailingContent,
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = MaterialTheme.colorScheme.onSurface,
            unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
            focusedBorderColor = MaterialTheme.colorScheme.primary,
            unfocusedBorderColor = MaterialTheme.colorScheme.outline,
            focusedLabelColor = MaterialTheme.colorScheme.primary,
            unfocusedLabelColor = MaterialTheme.colorScheme.onSurfaceVariant,
            cursorColor = MaterialTheme.colorScheme.primary,
            focusedContainerColor = MaterialTheme.colorScheme.surface,
            unfocusedContainerColor = MaterialTheme.colorScheme.surface,
        ),
    )
}
