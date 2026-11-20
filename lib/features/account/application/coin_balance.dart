import 'package:pili_aurora_next/features/account/data/profile_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

final class CoinBalance {
  CoinBalance._() {
    Accounts.mainChanges.addListener(_onAccountChanged);
  }

  static final instance = CoinBalance._();
  Account? _owner;
  num? _amount;
  int _revision = 0;

  num? get amount => identical(_owner, Accounts.main) ? _amount : null;

  void _onAccountChanged() {
    if (!identical(_owner, Accounts.main)) {
      _revision++;
      _owner = null;
      _amount = null;
    }
  }

  void confirm(Account account, num? amount) {
    if (!identical(account, Accounts.main)) return;
    _revision++;
    _owner = account;
    _amount = amount;
  }

  void recordSpend(Account account, int amount) {
    if (amount <= 0 || !identical(account, Accounts.main)) return;
    final before = this.amount;
    confirm(account, before == null ? null : before - amount);
  }

  Future<void> restore() async {
    final account = Accounts.main;
    if (!account.isLogin) return;
    final cached = const ProfileRepository().cached(account)?.money;
    if (cached != null) {
      confirm(account, cached);
    } else {
      await refresh();
    }
  }

  Future<void> refresh() async {
    final account = Accounts.main;
    if (!account.isLogin) return;
    final before = amount;
    _owner = account;
    _amount = before;
    final revision = ++_revision;
    final result = await const ProfileRepository().coins(account);
    if (result case Success(:final response) when revision == _revision) {
      confirm(account, response);
    }
  }
}
