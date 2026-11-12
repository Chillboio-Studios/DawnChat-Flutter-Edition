import 'package:flutter/material.dart';

import 'users_page.dart';

/// Deleted accounts — users and bots that have deleted their accounts.
class DeletedView extends StatelessWidget {
  const DeletedView({super.key, this.focusUserId});
  final String? focusUserId;

  @override
  Widget build(BuildContext context) =>
      UsersView(deletedOnly: true, focusUserId: focusUserId);
}
