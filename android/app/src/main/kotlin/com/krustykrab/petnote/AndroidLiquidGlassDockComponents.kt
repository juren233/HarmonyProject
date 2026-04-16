package com.krustykrab.petnote

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.spring
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.fastCoerceIn
import androidx.compose.ui.util.lerp
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberCombinedBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import com.kyant.backdrop.effects.vibrancy
import com.kyant.backdrop.highlight.Highlight
import com.kyant.backdrop.shadow.InnerShadow
import com.kyant.backdrop.shadow.Shadow
import com.kyant.shapes.Capsule
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.sign

private val LocalLiquidBottomTabScale =
    staticCompositionLocalOf { { 1f } }

@Composable
fun LiquidBottomTabs(
    selectedTabIndex: () -> Int,
    onTabSelected: (index: Int) -> Unit,
    prewarmRequestToken: Int = 0,
    onPrewarmCompleted: () -> Unit = {},
    backdrop: Backdrop,
    tabsCount: Int,
    selectionSlotIndexes: List<Int> = List(tabsCount) { it },
    isDarkTheme: Boolean,
    containerColor: Color,
    modifier: Modifier = Modifier,
    content: @Composable RowScope.((Int) -> Unit) -> Unit,
    effectContent: @Composable RowScope.() -> Unit = {},
) {
    val isLightTheme = !isDarkTheme

    val tabsBackdrop = rememberLayerBackdrop()

    BoxWithConstraints(
        modifier,
        contentAlignment = Alignment.CenterStart,
    ) {
        val normalizedSelectionSlotIndexes = remember(selectionSlotIndexes, tabsCount) {
            selectionSlotIndexes
                .filter { it in 0 until tabsCount }
                .ifEmpty { List(tabsCount) { it } }
        }
        val selectedIndex = selectedTabIndex().coerceIn(0, normalizedSelectionSlotIndexes.lastIndex)
        val selectedSlotValue = normalizedSelectionSlotIndexes[selectedIndex].toFloat()
        val density = LocalDensity.current
        val tabWidth = with(density) {
            (constraints.maxWidth.toFloat() - 8.dp.toPx()) / tabsCount
        }

        val offsetAnimation = remember { Animatable(0f) }
        val panelOffset by remember(density) {
            derivedStateOf {
                val fraction = (offsetAnimation.value / constraints.maxWidth).fastCoerceIn(-1f, 1f)
                with(density) {
                    4.dp.toPx() * fraction.sign * EaseOut.transform(abs(fraction))
                }
            }
        }

        val isLtr = LocalLayoutDirection.current == LayoutDirection.Ltr
        val animationScope = rememberCoroutineScope()
        var currentIndex by remember {
            mutableIntStateOf(selectedIndex)
        }
        lateinit var dampedDragAnimation: DampedDragAnimation
        val animateSelectionTo: (Int) -> Unit = { index ->
            dampedDragAnimation.animateToValue(
                normalizedSelectionSlotIndexes[index].toFloat(),
            )
        }
        dampedDragAnimation = remember(animationScope, normalizedSelectionSlotIndexes) {
            DampedDragAnimation(
                animationScope = animationScope,
                initialValue = selectedSlotValue,
                valueRange = normalizedSelectionSlotIndexes.first().toFloat()..
                    normalizedSelectionSlotIndexes.last().toFloat(),
                visibilityThreshold = 0.001f,
                initialScale = 1f,
                pressedScale = 78f / 56f,
                onDragStarted = {},
                onDragStopped = {
                    val targetIndex =
                        nearestSelectionIndexForValue(targetValue, normalizedSelectionSlotIndexes)
                    val targetSlotValue = normalizedSelectionSlotIndexes[targetIndex].toFloat()
                    val hasSelectionChanged = currentIndex != targetIndex
                    val shouldSnapSelection =
                        !hasSelectionChanged && abs(targetValue - targetSlotValue) > 0.001f
                    if (hasSelectionChanged || shouldSnapSelection) {
                        if (shouldSnapSelection) {
                            updateValue(targetSlotValue)
                        }
                    }
                    if (hasSelectionChanged) {
                        currentIndex = targetIndex
                        animateSelectionTo(targetIndex)
                        onTabSelected(targetIndex)
                    }
                    animationScope.launch {
                        offsetAnimation.animateTo(
                            0f,
                            spring(1f, 300f, 0.5f),
                        )
                    }
                },
                onDrag = { _, dragAmount ->
                    updateValue(
                        (targetValue + dragAmount.x / tabWidth * if (isLtr) 1f else -1f)
                            .fastCoerceIn(
                                normalizedSelectionSlotIndexes.first().toFloat(),
                                normalizedSelectionSlotIndexes.last().toFloat(),
                            ),
                    )
                    animationScope.launch {
                        offsetAnimation.snapTo(offsetAnimation.value + dragAmount.x)
                    }
                },
            )
        }
        val requestTabSelection: (Int) -> Unit = { index ->
            val normalizedIndex = index.coerceIn(0, normalizedSelectionSlotIndexes.lastIndex)
            val targetSlotValue = normalizedSelectionSlotIndexes[normalizedIndex].toFloat()
            val hasSelectionChanged = currentIndex != normalizedIndex
            val shouldSnapSelection =
                !hasSelectionChanged &&
                    abs(dampedDragAnimation.targetValue - targetSlotValue) > 0.001f
            if (shouldSnapSelection) {
                dampedDragAnimation.updateValue(targetSlotValue)
            }
            if (hasSelectionChanged) {
                currentIndex = normalizedIndex
                animateSelectionTo(normalizedIndex)
                onTabSelected(normalizedIndex)
            }
        }
        LaunchedEffect(selectedIndex) {
            if (currentIndex != selectedIndex) {
                currentIndex = selectedIndex
                animateSelectionTo(selectedIndex)
            }
        }

        val interactiveHighlight = remember(animationScope) {
            InteractiveHighlight(
                animationScope = animationScope,
                position = { size, offset ->
                    Offset(
                        if (isLtr) (dampedDragAnimation.value + 0.5f) * tabWidth + panelOffset
                        else size.width - (dampedDragAnimation.value + 0.5f) * tabWidth + panelOffset,
                        size.height / 2f,
                    )
                },
            )
        }

        LaunchedEffect(prewarmRequestToken) {
            if (prewarmRequestToken <= 0) {
                return@LaunchedEffect
            }
            val currentSlotIndex = normalizedSelectionSlotIndexes
                .getOrElse(currentIndex) { normalizedSelectionSlotIndexes.first() }
                .toFloat()
            val prewarmSelectionIndex = when {
                normalizedSelectionSlotIndexes.size <= 1 -> currentSlotIndex
                currentIndex < normalizedSelectionSlotIndexes.lastIndex ->
                    normalizedSelectionSlotIndexes[currentIndex + 1].toFloat()
                else -> normalizedSelectionSlotIndexes[currentIndex - 1].toFloat()
            }
            val prewarmPosition = Offset(
                if (isLtr) (prewarmSelectionIndex + 0.5f) * tabWidth
                else constraints.maxWidth.toFloat() - (prewarmSelectionIndex + 0.5f) * tabWidth,
                with(density) { 28.dp.toPx() },
            )
            val highlightPrewarm = launch { interactiveHighlight.prewarm(prewarmPosition) }
            val dragPrewarm = launch {
                if (abs(prewarmSelectionIndex - currentSlotIndex) > 0.001f) {
                    dampedDragAnimation.prewarmSelectionCycle(prewarmSelectionIndex)
                } else {
                    dampedDragAnimation.prewarmReleaseCycle()
                }
            }
            highlightPrewarm.join()
            dragPrewarm.join()
            onPrewarmCompleted()
        }

        Row(
            Modifier
                .graphicsLayer {
                    translationX = panelOffset
                }
                .drawBackdrop(
                    backdrop = backdrop,
                    shape = { Capsule() },
                    effects = {
                        vibrancy()
                        blur(8.dp.toPx())
                        lens(24.dp.toPx(), 24.dp.toPx())
                    },
                    layerBlock = {
                        val progress = dampedDragAnimation.pressProgress
                        val scale = lerp(1f, 1f + 16.dp.toPx() / size.width, progress)
                        scaleX = scale
                        scaleY = scale
                    },
                    onDrawSurface = { drawRect(containerColor) },
                )
                .then(interactiveHighlight.modifier)
                .height(64.dp)
                .fillMaxWidth()
                .padding(4.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = { content(requestTabSelection) },
        )

        CompositionLocalProvider(
            LocalLiquidBottomTabScale provides {
                lerp(1f, 1.2f, dampedDragAnimation.pressProgress)
            },
        ) {
            Row(
                Modifier
                    .clearAndSetSemantics {}
                    .alpha(0f)
                    .layerBackdrop(tabsBackdrop)
                    .graphicsLayer {
                        translationX = panelOffset
                    }
                    .drawBackdrop(
                        backdrop = backdrop,
                        shape = { Capsule() },
                        effects = {
                            val progress = dampedDragAnimation.pressProgress
                            vibrancy()
                            blur(8.dp.toPx())
                            lens(
                                24.dp.toPx() * progress,
                                24.dp.toPx() * progress,
                            )
                        },
                        highlight = {
                            val progress = dampedDragAnimation.pressProgress
                            Highlight.Default.copy(alpha = progress)
                        },
                        onDrawSurface = { drawRect(containerColor) },
                    )
                    .then(interactiveHighlight.modifier)
                    .height(56.dp)
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                content = effectContent,
            )
        }

        Box(
            Modifier
                .padding(horizontal = 4.dp)
                .graphicsLayer {
                    translationX =
                        if (isLtr) dampedDragAnimation.value * tabWidth + panelOffset
                        else size.width - (dampedDragAnimation.value + 1f) * tabWidth + panelOffset
                }
                .then(interactiveHighlight.gestureModifier)
                .then(dampedDragAnimation.modifier)
                .drawBackdrop(
                    backdrop = rememberCombinedBackdrop(backdrop, tabsBackdrop),
                    shape = { Capsule() },
                    effects = {
                        val progress = dampedDragAnimation.pressProgress
                        lens(
                            10.dp.toPx() * progress,
                            14.dp.toPx() * progress,
                            chromaticAberration = true,
                        )
                    },
                    highlight = {
                        val progress = dampedDragAnimation.pressProgress
                        Highlight.Default.copy(alpha = progress)
                    },
                    shadow = {
                        val progress = dampedDragAnimation.pressProgress
                        Shadow(alpha = progress)
                    },
                    innerShadow = {
                        val progress = dampedDragAnimation.pressProgress
                        InnerShadow(
                            radius = 8.dp * progress,
                            alpha = progress,
                        )
                    },
                    layerBlock = {
                        scaleX = dampedDragAnimation.scaleX
                        scaleY = dampedDragAnimation.scaleY
                        val velocity = dampedDragAnimation.velocity / 10f
                        scaleX /= 1f - (velocity * 0.75f).fastCoerceIn(-0.2f, 0.2f)
                        scaleY *= 1f - (velocity * 0.25f).fastCoerceIn(-0.2f, 0.2f)
                    },
                    onDrawSurface = {
                        val progress = dampedDragAnimation.pressProgress
                        drawRect(
                            if (isLightTheme) Color.Black.copy(0.1f)
                            else Color.White.copy(0.1f),
                            alpha = 1f - progress,
                        )
                        drawRect(Color.Black.copy(alpha = 0.03f * progress))
                    },
                )
                .height(56.dp)
                .fillMaxWidth(1f / tabsCount),
        )

    }
}

@Composable
fun RowScope.LiquidBottomTab(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val scale = LocalLiquidBottomTabScale.current
    Column(
        modifier
            .clip(Capsule())
            .clickable(
                interactionSource = null,
                indication = null,
                role = Role.Tab,
                onClick = onClick,
            )
            .fillMaxHeight()
            .weight(1f)
            .graphicsLayer {
                val currentScale = scale()
                scaleX = currentScale
                scaleY = currentScale
            },
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
        content = content,
    )
}

@Composable
fun RowScope.LiquidBottomVisualSlot(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val scale = LocalLiquidBottomTabScale.current
    Column(
        modifier
            .fillMaxHeight()
            .weight(1f)
            .graphicsLayer {
                val currentScale = scale()
                scaleX = currentScale
                scaleY = currentScale
            },
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
        content = content,
    )
}

@Composable
fun RowScope.LiquidBottomVisualActionSlot(
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier
            .fillMaxHeight()
            .weight(1f),
        contentAlignment = Alignment.Center,
        content = content,
    )
}

private fun nearestSelectionIndexForValue(
    value: Float,
    selectionSlotIndexes: List<Int>,
): Int {
    var nearestIndex = 0
    var nearestDistance = Float.MAX_VALUE
    selectionSlotIndexes.forEachIndexed { index, slot ->
        val distance = abs(slot - value)
        if (distance < nearestDistance) {
            nearestDistance = distance
            nearestIndex = index
        }
    }
    return nearestIndex
}

@Composable
fun RowScope.LiquidBottomActionSlot(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier
            .clip(Capsule())
            .clickable(
                interactionSource = null,
                indication = null,
                role = Role.Button,
                onClick = onClick,
            )
            .fillMaxHeight()
            .weight(1f),
        contentAlignment = Alignment.Center,
        content = content,
    )
}

@Composable
fun RowScope.LiquidBottomPlaceholderSlot(
    modifier: Modifier = Modifier,
) {
    Box(
        modifier
            .fillMaxHeight()
            .weight(1f),
    )
}


