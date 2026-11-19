import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crusam/features/society/core/society_context.dart';

class SocietyPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? filters;
  final Widget child;
  final bool requireSociety;
  final bool allowAllSocieties;

  const SocietyPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.filters,
    required this.child,
    this.requireSociety = true,
    this.allowAllSocieties = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SocietyContext.instance,
      builder: (context, _) {
        final ctx = SocietyContext.instance;

        if (requireSociety && !allowAllSocieties && (ctx.allSocieties || ctx.societyId == null)) {
          return const SocietyRequiredView();
        }

        if (requireSociety && allowAllSocieties && !ctx.allSocieties && ctx.societyId == null) {
          return const SocietyRequiredView();
        }

        return Container(
          key: ValueKey<int>(ctx.societyId ?? -1),
          color: const Color(0xFFF8FAFC), // AppColors.slate50
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (actions != null && actions!.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < actions!.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          actions![i],
                        ],
                      ],
                    ),
                  ],
                ],
              ),
              if (filters != null) ...[
                const SizedBox(height: 16),
                filters!,
              ],
              const SizedBox(height: 16),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

class SocietyRequiredView extends StatelessWidget {
  const SocietyRequiredView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.apartment_outlined, size: 48, color: Color(0xFF94A3B8)),
              const SizedBox(height: 16),
              const Text(
                'Please Select a Society',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              const Text(
                'This section requires a single society context. Please select one from the top bar.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.list_alt, size: 16),
                label: const Text('View All Societies'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () => context.go('/society/societies'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
