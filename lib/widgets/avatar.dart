import 'package:flutter/cupertino.dart';

import '../app_state.dart';

/// Фото из ЛК, а если его нет — инициалы «Имя Фамилия» на сером круге,
/// как у контактов в iOS.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.state, required this.size});

  final AppState state;
  final double size;

  String get _initials {
    final parts = (state.fullName ?? '').split(' ');
    if (parts.length < 2) return '';
    return '${parts[1].characters.first}${parts[0].characters.first}';
  }

  @override
  Widget build(BuildContext context) {
    final photo = state.photo;
    final initials = _initials;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: photo != null
            ? Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true)
            : ColoredBox(
                color: CupertinoColors.systemGrey4.resolveFrom(context),
                child: Center(
                  child: initials.isEmpty
                      ? Icon(
                          CupertinoIcons.person_fill,
                          size: size * 0.55,
                          color: CupertinoColors.white,
                        )
                      : Text(
                          initials,
                          style: TextStyle(
                            fontSize: size * 0.38,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.white,
                          ),
                        ),
                ),
              ),
      ),
    );
  }
}
