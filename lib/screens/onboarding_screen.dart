import 'package:flutter/material.dart';

/// Стартовый экран до входа: что это за приложение и куда уходит пароль.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onLogin, this.error});

  final VoidCallback onLogin;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset('assets/icon.png', width: 88, height: 88),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Расписание РАНХиГС',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              const _Block(
                title: 'Что это',
                text: 'Твоё расписание из личного кабинета.',
              ),
              const _Block(
                title: 'Как работает',
                text: 'Входишь в ЛК на странице сайта. Логин и пароль приложение не видит и не хранит.',
              ),
              const _Block(
                title: 'Что умеет',
                text: 'Работает без интернета, напоминает о парах, добавляет их в календарь и виджет.',
              ),
              const Spacer(flex: 3),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: onLogin,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: theme.textTheme.titleMedium,
                ),
                child: const Text('Войти через ЛК'),
              ),
              const SizedBox(height: 14),
              Text(
                'Неофициальное приложение',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
