import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef AccountRoleSelection = ({List<int> roles, Map<int, String> options});

class AccountRoles {
  const AccountRoles();

  AccountRoleSelection selection() => (
    roles: List.unmodifiable(
      AccountType.values.map((role) => Accounts.get(role).mid),
    ),
    options: Map.unmodifiable({
      0: '0',
      for (final account in Accounts.account.values)
        account.mid: '${account.mid}',
    }),
  );

  Future<bool> apply(AccountRoleSelection original, List<int> selected) async {
    if (selected.length != AccountType.values.length) return false;
    final updates = <AccountType, Account>{};
    for (final role in AccountType.values) {
      final current = Accounts.get(role);
      final previous = original.roles[role.index];
      final mid = selected[role.index];
      if (current.mid != previous) return false;
      if (mid == previous) continue;
      final next = mid == 0 ? AnonymousAccount() : Accounts.account.get('$mid');
      if (next == null) return false;
      updates[role] = next;
    }
    await Future.wait(
      updates.entries.map((entry) => Accounts.set(entry.key, entry.value)),
    );
    return true;
  }
}
