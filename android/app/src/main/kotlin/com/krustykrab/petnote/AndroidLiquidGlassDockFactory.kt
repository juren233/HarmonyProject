package com.krustykrab.petnote

import android.content.Context
import android.view.View
import android.view.ViewTreeObserver
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Pets
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kyant.backdrop.backdrops.rememberCanvasBackdrop
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class AndroidLiquidGlassDockFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return AndroidLiquidGlassDockPlatformView(
            context = context,
            messenger = messenger,
            viewId = viewId,
            args = args as? Map<String, Any?>,
        )
    }
}

private class AndroidLiquidGlassDockPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    args: Map<String, Any?>?,
) : PlatformView {
    private val composeView = ComposeView(context)
    private val channel = MethodChannel(messenger, "petnote/android_liquid_glass_dock_$viewId")

    private var selectedTabName by mutableStateOf(
        args?.get("selectedTab") as? String ?: "checklist",
    )
    private var brightnessName by mutableStateOf(
        args?.get("brightness") as? String ?: "light",
    )
    private var bottomInset by mutableStateOf(
        (args?.get("bottomInset") as? Number)?.toFloat() ?: 0f,
    )
    private var shouldPrewarmFirstInteraction by mutableStateOf(
        args?.get("shouldPrewarmFirstInteraction") as? Boolean ?: false,
    )
    private var hasRequestedFirstInteractionPrewarm = false
    private var hasCompletedFirstInteractionPrewarm = false
    private var hasReportedFirstLayout = false
    private var prewarmRequestToken by mutableStateOf(0)

    init {
        composeView.setViewCompositionStrategy(
            ViewCompositionStrategy.DisposeOnDetachedFromWindow,
        )
        composeView.viewTreeObserver.addOnGlobalLayoutListener(
            object : ViewTreeObserver.OnGlobalLayoutListener {
                override fun onGlobalLayout() {
                    if (hasReportedFirstLayout || composeView.width <= 0 || composeView.height <= 0) {
                        return
                    }
                    hasReportedFirstLayout = true
                    if (composeView.viewTreeObserver.isAlive) {
                        composeView.viewTreeObserver.removeOnGlobalLayoutListener(this)
                    }
                    maybeRequestFirstInteractionPrewarm()
                }
            },
        )
        composeView.setContent {
            AndroidLiquidGlassDockContent(
                selectedTabName = selectedTabName,
                brightnessName = brightnessName,
                bottomInset = bottomInset,
                prewarmRequestToken = prewarmRequestToken,
                onPrewarmCompleted = ::notifyFirstInteractionPrewarmed,
                onTabSelected = { tabName ->
                    selectedTabName = tabName
                    channel.invokeMethod("tabSelected", tabName)
                },
                onAddTapped = {
                    channel.invokeMethod("addTapped", null)
                },
            )
        }
        channel.setMethodCallHandler(::onMethodCall)
    }

    override fun getView(): View = composeView

    override fun dispose() {
        channel.setMethodCallHandler(null)
        composeView.disposeComposition()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setSelectedTab" -> {
                selectedTabName = call.arguments as? String ?: selectedTabName
                result.success(null)
            }

            "setBrightness" -> {
                brightnessName = call.arguments as? String ?: brightnessName
                result.success(null)
            }

            "prewarmFirstInteraction" -> {
                shouldPrewarmFirstInteraction = true
                maybeRequestFirstInteractionPrewarm()
                result.success(null)
            }

            "resetFirstInteractionPrewarm" -> {
                resetFirstInteractionPrewarmState()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun maybeRequestFirstInteractionPrewarm() {
        if (!shouldPrewarmFirstInteraction ||
            hasRequestedFirstInteractionPrewarm ||
            !hasReportedFirstLayout
        ) {
            return
        }
        hasRequestedFirstInteractionPrewarm = true
        prewarmRequestToken += 1
    }

    private fun notifyFirstInteractionPrewarmed() {
        if (hasCompletedFirstInteractionPrewarm) {
            return
        }
        hasCompletedFirstInteractionPrewarm = true
        channel.invokeMethod("firstInteractionPrewarmed", null)
    }

    private fun resetFirstInteractionPrewarmState() {
        shouldPrewarmFirstInteraction = false
        hasRequestedFirstInteractionPrewarm = false
        hasCompletedFirstInteractionPrewarm = false
        prewarmRequestToken = 0
    }
}

private data class DockTabSpec(
    val key: String,
    val label: String,
    val icon: ImageVector,
    val accentColor: Color,
    val isAddAction: Boolean = false,
)

private val dockTabs = listOf(
    DockTabSpec("checklist", "清单", Icons.Rounded.Checklist, Color(0xFFF2A65A)),
    DockTabSpec("overview", "总览", Icons.Rounded.AutoAwesome, Color(0xFF9B84E8)),
    DockTabSpec("add", "新增", Icons.Rounded.Add, Color.Transparent, isAddAction = true),
    DockTabSpec("pets", "爱宠", Icons.Rounded.Pets, Color(0xFFFFA79B)),
    DockTabSpec("me", "我的", Icons.Rounded.Person, Color(0xFFA5C6FF)),
)

private val navigationTabs = dockTabs.filterNot { it.isAddAction }

private data class DockThemePalette(
    val backdropColor: Color,
    val navBackground: Color,
    val navIconInactive: Color,
    val navLabelInactive: Color,
    val addGradientStart: Color,
    val addGradientEnd: Color,
    val addShadow: Color,
)

private val lightDockThemePalette =
    DockThemePalette(
        backdropColor = Color(0xFFF5F2EC),
        navBackground = Color(0xCCFFFFFF),
        navIconInactive = Color(0xFF7E8492),
        navLabelInactive = Color(0xFF7E8492),
        addGradientStart = Color(0xFF90CE9B),
        addGradientEnd = Color(0xFF6AB57A),
        addShadow = Color(0x226AB57A),
    )

private val darkDockThemePalette =
    DockThemePalette(
        backdropColor = Color(0xFF020304),
        navBackground = Color(0xE6060709),
        navIconInactive = Color(0xFFA1A8B4),
        navLabelInactive = Color(0xFFA1A8B4),
        addGradientStart = Color(0xFF73B87F),
        addGradientEnd = Color(0xFF528F63),
        addShadow = Color(0x40192E1D),
    )

@Composable
private fun AndroidLiquidGlassDockContent(
    selectedTabName: String,
    brightnessName: String,
    bottomInset: Float,
    prewarmRequestToken: Int = 0,
    onPrewarmCompleted: () -> Unit,
    onTabSelected: (String) -> Unit,
    onAddTapped: () -> Unit,
) {
    val isDarkTheme = brightnessName == "dark"
    val palette = if (isDarkTheme) darkDockThemePalette else lightDockThemePalette
    val contentColor = palette.navLabelInactive
    val iconColorFilter = ColorFilter.tint(palette.navIconInactive)
    val selectedAccentColor =
        navigationTabs.firstOrNull { it.key == selectedTabName }?.accentColor
            ?: navigationTabs.first().accentColor
    val backdrop = rememberCanvasBackdrop {
        drawRect(palette.backdropColor)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(
                start = 16.dp,
                top = 10.dp,
                end = 16.dp,
                bottom = 12.dp + bottomInset.dp,
            ),
        contentAlignment = Alignment.BottomCenter,
    ) {
        key(isDarkTheme, palette.navBackground, palette.backdropColor) {
            LiquidBottomTabs(
                selectedTabIndex = {
                    navigationTabs.indexOfFirst { it.key == selectedTabName }.coerceAtLeast(0)
                },
                onTabSelected = { index ->
                    onTabSelected(navigationTabs[index].key)
                },
                prewarmRequestToken = prewarmRequestToken,
                onPrewarmCompleted = onPrewarmCompleted,
                backdrop = backdrop,
                tabsCount = dockTabs.size,
                selectionSlotIndexes = listOf(0, 1, 3, 4),
                isDarkTheme = isDarkTheme,
                containerColor = palette.navBackground,
                modifier = Modifier.fillMaxWidth(),
                content = { requestTabSelection ->
                    dockTabs.forEach { spec ->
                        if (spec.isAddAction) {
                            LiquidBottomActionSlot(onClick = onAddTapped) {
                                AndroidLiquidGlassAddButton(
                                    addGradientStart = palette.addGradientStart,
                                    addGradientEnd = palette.addGradientEnd,
                                    addShadow = palette.addShadow,
                                    onClick = null,
                                )
                            }
                        } else {
                            val navigationIndex =
                                navigationTabs.indexOfFirst { it.key == spec.key }.coerceAtLeast(0)
                            LiquidBottomTab(
                                onClick = {
                                    requestTabSelection(navigationIndex)
                                },
                            ) {
                                Image(
                                    painter = rememberVectorPainter(spec.icon),
                                    contentDescription = spec.label,
                                    modifier = Modifier.size(24.dp),
                                    colorFilter = iconColorFilter,
                                )
                                BasicText(
                                    spec.label,
                                    style = TextStyle(
                                        color = contentColor,
                                        fontSize = 11.sp,
                                    ),
                                )
                            }
                        }
                    }
                },
                effectContent = {
                    dockTabs.forEach { spec ->
                        if (spec.isAddAction) {
                            LiquidBottomVisualActionSlot {
                                AndroidLiquidGlassAddButton(
                                    addGradientStart = palette.addGradientStart,
                                    addGradientEnd = palette.addGradientEnd,
                                    addShadow = palette.addShadow,
                                    onClick = null,
                                )
                            }
                        } else {
                            LiquidBottomVisualSlot {
                                Image(
                                    painter = rememberVectorPainter(spec.icon),
                                    contentDescription = spec.label,
                                    modifier = Modifier.size(24.dp),
                                    colorFilter = ColorFilter.tint(selectedAccentColor),
                                )
                                BasicText(
                                    spec.label,
                                    style = TextStyle(
                                        color = selectedAccentColor,
                                        fontSize = 11.sp,
                                    ),
                                )
                            }
                        }
                    }
                },
            )
        }
    }
}

@Composable
private fun AndroidLiquidGlassAddButton(
    addGradientStart: Color,
    addGradientEnd: Color,
    addShadow: Color,
    onClick: (() -> Unit)? = null,
) {
    Box(
        modifier = Modifier
            .size(52.dp)
            .then(
                if (onClick != null) {
                    Modifier
                        .clip(CircleShape)
                        .clickable(onClick = onClick)
                } else {
                    Modifier
                },
            )
            .graphicsLayer {
                shadowElevation = 18.dp.toPx()
                shape = CircleShape
                clip = false
                ambientShadowColor = addShadow
                spotShadowColor = addShadow
            }
            .background(
                brush = Brush.linearGradient(
                    colors = listOf(addGradientStart, addGradientEnd),
                ),
                shape = CircleShape,
            )
            .border(
                width = 1.4.dp,
                color = Color(0xAAFFFFFF),
                shape = CircleShape,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = rememberVectorPainter(Icons.Filled.Add),
            contentDescription = "新增",
            colorFilter = ColorFilter.tint(Color.White),
            modifier = Modifier.size(26.dp),
        )
    }
}
