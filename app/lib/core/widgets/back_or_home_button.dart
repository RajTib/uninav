import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// AppBar leading that always gives the user a way out: pops the stack when
/// there is history, otherwise jumps to home. Needed because deep links
/// (/map?room=x) can land on a screen with an empty stack, where the default
/// back arrow would not appear at all.
class BackOrHomeButton extends StatelessWidget {
  const BackOrHomeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BackButton(
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
    );
  }
}
