import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:petnote/app/app_theme.dart';
import 'package:petnote/app/interaction_feedback.dart';
import 'package:petnote/platform/pet_photo_path_resolver.dart';

const String petPhotoIntroHeroAssetPath =
    'assets/images/intro/first_page_hero.svg';
const Color petPhotoPlaceholderIdleIconColor = Color(0xFFB8BEC8);
const Color petPhotoPlaceholderPressedIconColor = Color(0xFFF2A65A);
const Color petPhotoPlaceholderIdleSurfaceColor = Color(0xFFF6F7FA);
const Color petPhotoPlaceholderPressedSurfaceColor = Color(0xFFFBE8D8);

Widget Function({
  required String photoPath,
  required BoxFit fit,
  required Widget fallback,
})? debugPetPhotoImageBuilder;

bool Function(String? photoPath)? debugHasPetPhotoOverride;

bool hasPetPhoto(String? photoPath) {
  final override = debugHasPetPhotoOverride;
  if (override != null) {
    return override(photoPath);
  }
  if (photoPath == null || photoPath.trim().isEmpty) {
    return false;
  }
  return PetPhotoPathResolver.resolveExistingPath(photoPath) != null;
}

bool _isAnimalEmojiFallback(String text) {
  return switch (text.trim()) {
    '🐱' || '🐶' || '🐰' || '🐦' => true,
    _ => false,
  };
}

class PetPhotoAvatar extends StatelessWidget {
  const PetPhotoAvatar({
    super.key,
    required this.photoPath,
    required this.fallbackText,
    required this.radius,
    required this.backgroundColor,
    required this.foregroundColor,
    this.fallbackTextStyle,
  });

  final String? photoPath;
  final String fallbackText;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;
  final TextStyle? fallbackTextStyle;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final fallback = _buildFallback();
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: backgroundColor,
        child: hasPetPhoto(photoPath)
            ? _buildPhoto(photoPath!, fallback)
            : fallback,
      ),
    );
  }

  Widget _buildPhoto(String resolvedPhotoPath, Widget fallback) {
    final photoPath =
        PetPhotoPathResolver.resolveExistingPath(resolvedPhotoPath) ??
            resolvedPhotoPath;
    final imageBuilder = debugPetPhotoImageBuilder;
    if (imageBuilder != null) {
      return imageBuilder(
        photoPath: photoPath,
        fit: BoxFit.cover,
        fallback: fallback,
      );
    }
    return Image.file(
      File(photoPath),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  Widget _buildFallback() {
    final isAnimalEmoji = _isAnimalEmojiFallback(fallbackText);
    final effectiveStyle = fallbackTextStyle ??
        TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        );
    final contentPadding = isAnimalEmoji ? radius * 0.04 : radius * 0.18;
    final emojiScale = isAnimalEmoji ? 1.55 : 1.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(contentPadding),
        child: FittedBox(
          fit: BoxFit.contain,
          child: Transform.scale(
            scale: emojiScale,
            child: Text(
              fallbackText,
              maxLines: 1,
              softWrap: false,
              style: effectiveStyle,
            ),
          ),
        ),
      ),
    );
  }
}

class PetPhotoSquare extends StatelessWidget {
  const PetPhotoSquare({
    super.key,
    required this.photoPath,
    required this.size,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.fallback,
  });

  final String? photoPath;
  final double size;
  final BorderRadius borderRadius;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final effectiveFallback = fallback ?? const SizedBox.shrink();
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: hasPetPhoto(photoPath)
            ? _buildPhoto(photoPath!, effectiveFallback)
            : effectiveFallback,
      ),
    );
  }

  Widget _buildPhoto(String resolvedPhotoPath, Widget fallback) {
    final photoPath =
        PetPhotoPathResolver.resolveExistingPath(resolvedPhotoPath) ??
            resolvedPhotoPath;
    final imageBuilder = debugPetPhotoImageBuilder;
    if (imageBuilder != null) {
      return imageBuilder(
        photoPath: photoPath,
        fit: BoxFit.cover,
        fallback: fallback,
      );
    }
    return Image.file(
      File(photoPath),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class PetPhotoContainFrame extends StatelessWidget {
  const PetPhotoContainFrame({
    super.key,
    required this.photoPath,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.fallback,
  });

  final String? photoPath;
  final BorderRadius borderRadius;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final effectiveFallback = fallback ?? const SizedBox.shrink();
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox.expand(
        child: hasPetPhoto(photoPath)
            ? _buildPhoto(photoPath!, effectiveFallback)
            : effectiveFallback,
      ),
    );
  }

  Widget _buildPhoto(String resolvedPhotoPath, Widget fallback) {
    final photoPath =
        PetPhotoPathResolver.resolveExistingPath(resolvedPhotoPath) ??
            resolvedPhotoPath;
    final imageBuilder = debugPetPhotoImageBuilder;
    if (imageBuilder != null) {
      return imageBuilder(
        photoPath: photoPath,
        fit: BoxFit.contain,
        fallback: fallback,
      );
    }
    return Image.file(
      File(photoPath),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class PetPhotoPickerCard extends StatefulWidget {
  const PetPhotoPickerCard({
    super.key,
    required this.photoPath,
    required this.onTap,
    this.enabled = true,
    this.title = '宠物照片',
    this.subtitle = '选一张照片作为爱宠头像，稍后也能继续更换。',
  });

  final String? photoPath;
  final Future<void> Function() onTap;
  final bool enabled;
  final String title;
  final String subtitle;

  @override
  State<PetPhotoPickerCard> createState() => _PetPhotoPickerCardState();
}

class _PetPhotoPickerCardState extends State<PetPhotoPickerCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.petNoteTokens;
    final hasPhoto = hasPetPhoto(widget.photoPath);
    final compact = MediaQuery.sizeOf(context).height <= 700;
    final placeholderSize = compact ? 112.0 : 172.0;
    final iconSize = compact ? 72.0 : 108.0;
    final titleText = hasPhoto ? '点击更换图片' : '添加宠物图片';
    final subtitleText = hasPhoto ? '这张图片会同步显示在爱宠档案页。' : widget.subtitle;
    final sectionTitle = widget.title.trim();
    return SizedBox(
      key: const ValueKey('pet_photo_picker_card'),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (sectionTitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                sectionTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: tokens.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          GestureDetector(
            key: const ValueKey('pet_photo_picker_button'),
            onTap: widget.enabled ? () => widget.onTap() : null,
            onTapDown: widget.enabled
                ? (_) {
                    if (!hasPhoto) {
                      triggerLightImpactHaptic();
                    }
                    setState(() => _pressed = true);
                  }
                : null,
            onTapUp:
                widget.enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel:
                widget.enabled ? () => setState(() => _pressed = false) : null,
            child: hasPhoto
                ? _buildPhotoPreview(
                    placeholderSize: placeholderSize,
                  )
                : _buildPlaceholderButton(
                    placeholderSize: placeholderSize,
                    iconSize: iconSize,
                  ),
          ),
          SizedBox(height: compact ? 10 : 18),
          Text(
            titleText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: tokens.primaryText,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitleText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.secondaryText,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoPreview({
    required double placeholderSize,
  }) {
    return ClipOval(
      child: SizedBox(
        width: placeholderSize,
        height: placeholderSize,
        child: Image.file(
          File(widget.photoPath!),
          key: const ValueKey('pet_photo_picker_preview'),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholderButton(
            placeholderSize: placeholderSize,
            iconSize: placeholderSize * 0.63,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderButton({
    required double placeholderSize,
    required double iconSize,
  }) {
    final surfaceColor = _pressed
        ? petPhotoPlaceholderPressedSurfaceColor
        : petPhotoPlaceholderIdleSurfaceColor;
    final iconColor = _pressed
        ? petPhotoPlaceholderPressedIconColor
        : petPhotoPlaceholderIdleIconColor;
    return AnimatedScale(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      scale: _pressed ? 0.94 : 1,
      child: AnimatedContainer(
        key: const ValueKey('pet_photo_picker_placeholder_surface'),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: placeholderSize,
        height: placeholderSize,
        decoration: BoxDecoration(
          color: surfaceColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0x24000000),
              blurRadius: _pressed ? 8 : 20,
              offset: Offset(0, _pressed ? 4 : 12),
            ),
          ],
        ),
        child: Center(
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            offset: _pressed ? const Offset(0, 0.02) : Offset.zero,
            child: SvgPicture.asset(
              petPhotoIntroHeroAssetPath,
              key: const ValueKey('pet_photo_picker_placeholder_icon'),
              width: iconSize,
              height: iconSize,
              fit: BoxFit.contain,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}
