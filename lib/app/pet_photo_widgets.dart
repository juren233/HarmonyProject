import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:petnote/app/app_theme.dart';

const String petPhotoIntroHeroAssetPath = 'assets/images/intro/first_page_hero.svg';
const Color petPhotoPlaceholderIdleIconColor = Color(0xFFB8BEC8);
const Color petPhotoPlaceholderPressedIconColor = Color(0xFFF2A65A);
const Color petPhotoPlaceholderIdleSurfaceColor = Color(0xFFF6F7FA);
const Color petPhotoPlaceholderPressedSurfaceColor = Color(0xFFFBE8D8);

bool hasPetPhoto(String? photoPath) {
  if (photoPath == null || photoPath.trim().isEmpty) {
    return false;
  }
  try {
    return File(photoPath).existsSync();
  } catch (_) {
    return false;
  }
}

class PetPhotoAvatar extends StatelessWidget {
  const PetPhotoAvatar({
    super.key,
    required this.photoPath,
    required this.fallbackText,
    required this.radius,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String? photoPath;
  final String fallbackText;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: backgroundColor,
        child: hasPetPhoto(photoPath)
            ? Image.file(
                File(photoPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildFallback(),
              )
            : _buildFallback(),
      ),
    );
  }

  Widget _buildFallback() {
    return Center(
      child: Text(
        fallbackText,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
          fontSize: 12,
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
  });

  final String? photoPath;
  final double size;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: hasPetPhoto(photoPath)
            ? Image.file(
                File(photoPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            : const SizedBox.shrink(),
      ),
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
            onTapDown:
                widget.enabled ? (_) => setState(() => _pressed = true) : null,
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
    return AnimatedContainer(
      key: const ValueKey('pet_photo_picker_placeholder_surface'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: placeholderSize,
      height: placeholderSize,
      decoration: BoxDecoration(
        color: surfaceColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: SvgPicture.asset(
          petPhotoIntroHeroAssetPath,
          key: const ValueKey('pet_photo_picker_placeholder_icon'),
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
        ),
      ),
    );
  }
}
