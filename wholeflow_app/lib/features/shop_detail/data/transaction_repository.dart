import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/statement.dart';

part 'transaction_repository.g.dart';

/// A shop's statement from the WholeFlow app API. The server refuses staff
/// who may not see the company's transactions.
class TransactionRepository {
  TransactionRepository(this._api);

  final ApiClient _api;

  /// The whole ledger, newest first, with the balance after each voucher.
  Future<Statement> statement(String shopId) async {
    try {
      return Statement.fromJson(await _api.get('shops/$shopId/statement'));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// The ledger between two days (null = open end), with the balance brought forward.
  Future<PeriodStatement> period(String shopId, {DateTime? from, DateTime? to}) async {
    String day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      return PeriodStatement.fromJson(
        await _api.get('shops/$shopId/statement', {
          'from': ?(from == null ? null : day(from)),
          'to': ?(to == null ? null : day(to)),
        }),
      );
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

@Riverpod(keepAlive: true)
TransactionRepository transactionRepository(Ref ref) => TransactionRepository(ref.watch(apiClientProvider));
