import 'package:flutter/cupertino.dart';

/// Стартовый экран до входа: что это за приложение и куда уходит пароль.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onLogin, this.error});

  final VoidCallback onLogin;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoPageScaffold(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
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
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.36,
                  color: label,
                ),
              ),
              const SizedBox(height: 32),
              const _Block(
                title: 'Что это',
                text: 'Твоё расписание из личного кабинета.',
              ),
              const _Block(
                title: 'Как работает',
                text:
                    'Входишь в ЛК на странице сайта. Логин и пароль '
                    'приложение не видит и не хранит.',
              ),
              const _Block(
                title: 'Что умеет',
                text:
                    'Работает без интернета, напоминает о парах, добавляет '
                    'их в календарь и виджет.',
              ),
              const Spacer(flex: 3),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: CupertinoColors.systemRed.resolveFrom(context),
                    ),
                  ),
                ),
              CupertinoButton.filled(
                onPressed: onLogin,
                sizeStyle: CupertinoButtonSize.large,
                borderRadius: BorderRadius.circular(14),
                child: const Text(
                  'Войти через ЛК',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Неофициальное приложение',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: secondary),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.label.resolveFrom(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          text,
          style: TextStyle(
            fontSize: 17,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ],
    ),
  );
}
