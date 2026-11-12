import 'package:flutter/material.dart';

import 'users_page.dart';

/// Staff permission management — the user directory pre-filtered to
/// accounts with admin access, focused on the permission editor.
class StaffView extends StatelessWidget {
  const StaffView({super.key, this.focusUserId});
  final String? focusUserId;

  @override
  Widget build(BuildContext context) =>
      UsersView(staffOnly: true, focusUserId: focusUserId);
}
