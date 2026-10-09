import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shops/data/shop_repository.dart';
import '../../shops/domain/shop.dart';
import '../data/transaction_repository.dart';
import '../domain/statement.dart';

part 'shop_detail_providers.g.dart';

@riverpod
Future<ShopDetail> shopDetail(Ref ref, String shopId) => ref.watch(shopRepositoryProvider).detail(shopId);

/// The shop's whole ledger with running balances, worked out on the server.
@riverpod
Future<Statement> shopStatement(Ref ref, String shopId) => ref.watch(transactionRepositoryProvider).statement(shopId);

typedef StatementPeriodKey = ({String shopId, DateTime? from, DateTime? to});

/// The shop's statement between two days (for sharing with the customer).
final statementPeriodProvider = FutureProvider.autoDispose.family<PeriodStatement, StatementPeriodKey>(
  (ref, k) => ref.watch(transactionRepositoryProvider).period(k.shopId, from: k.from, to: k.to),
);

/// The Statement tab's date filter of a shop, kept here so "Share statement"
/// in the app bar can start from the same dates.
final statementRangeProvider = NotifierProvider.autoDispose.family<StatementRange, DateTimeRange?, String>(StatementRange.new);

class StatementRange extends Notifier<DateTimeRange?> {
  StatementRange(this.shopId);

  final String shopId;

  @override
  DateTimeRange? build() => null;

  void set(DateTimeRange? range) => state = range;
}
