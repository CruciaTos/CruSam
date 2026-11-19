import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crusam/core/theme/app_colors.dart';
import 'package:crusam/features/society/core/workspace_memory.dart';
import 'package:crusam/features/society/shared/widgets/workspace_transition.dart';

class WorkspaceSwitch extends StatelessWidget {
  final bool compact;

  const WorkspaceSwitch({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final isSociety = isSocietyLocation(path);

    final width = compact ? 132.0 : 172.0;
    const height = 34.0;

    return Tooltip(
      message: 'Switch workspace',
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFF334155),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _SegmentButton(
                label: 'CruSam',
                isSelected: !isSociety,
                selectedColor: const Color(0xFF3B82F6),
                compact: compact,
                onTap: () {
                  if (isSociety) {
                    final router = GoRouter.of(context);
                    final target = WorkspaceMemory.instance.lastCrusamPath;
                    final destination = target.isNotEmpty
                        ? target
                        : WorkspaceMemory.defaultCrusamPath;
                    unawaited(playWorkspaceTransition(
                      context,
                      toSociety: false,
                      onMidpoint: () => router.go(destination),
                    ));
                  }
                },
              ),
            ),
            Expanded(
              child: _SegmentButton(
                label: 'Society',
                isSelected: isSociety,
                selectedColor: AppColors.amber700,
                compact: compact,
                onTap: () {
                  if (!isSociety) {
                    final router = GoRouter.of(context);
                    final target = WorkspaceMemory.instance.lastSocietyPath;
                    final destination = target.isNotEmpty
                        ? target
                        : WorkspaceMemory.defaultSocietyPath;
                    unawaited(playWorkspaceTransition(
                      context,
                      toSociety: true,
                      onMidpoint: () => router.go(destination),
                    ));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final bool compact;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? selectedColor : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );
  }
}
