import 'package:flutter/material.dart';

import 'users_page.dart';

/// Disabled accounts — suspended or otherwise disabled users, for
/// support-ticket lookup.
class DisabledView extends StatelessWidget {
  const DisabledView({super.key, this.focusUserId});
  final String? focusUserId;

  @override
  Widget build(BuildContext context) =>
      UsersView(disabledOnly: true, focusUserId: focusUserId);
}
