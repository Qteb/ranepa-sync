import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../models.dart';

void showLessonSheet(BuildContext context, Lesson lesson) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _LessonSheet(lesson: lesson),
  );
}

class _LessonSheet extends StatelessWidget {
  const _LessonSheet({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lesson.subject, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                [
                  if (lesson.kind.isNotEmpty) lesson.kind,
                  if (lesson.cancelled) 'отменена',
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _Row(
                icon: Icons.schedule,
                text: '${dayTitle(lesson.start)}\n${timeRange(lesson)}',
              ),
              if (lesson.location.isNotEmpty)
                _Row(
                  icon: lesson.isRemote
                      ? Icons.videocam_outlined
                      : Icons.place_outlined,
                  text: lesson.room,
                ),
              if (lesson.lecturer.isNotEmpty)
                _Row(icon: Icons.person_outline, text: lesson.lecturer),
              if (lesson.email.isNotEmpty)
                _Row(
                  icon: Icons.mail_outline,
                  text: lesson.email,
                  onTap: () =>
                      launchUrl(Uri(scheme: 'mailto', path: lesson.email)),
                ),
              if (lesson.groups.isNotEmpty)
                _Row(
                  icon: Icons.groups_outlined,
                  text: lesson.groups.join(', '),
                ),
              if (lesson.comment.isNotEmpty)
                _Row(icon: Icons.notes, text: lesson.comment),
              if (lesson.lmsLink.isNotEmpty) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Открыть курс в СДО'),
                  onPressed: () => launchUrl(
                    Uri.parse(lesson.lmsLink),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: onTap == null
                    ? theme.textTheme.bodyMedium
                    : theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
