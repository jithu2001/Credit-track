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

@riverpod
Future<Statement> shopStatement(Ref ref, String shopId) async {
  final shop = await ref.watch(shopDetailProvider(shopId).future);
  final txns = await ref.watch(transactionRepositoryProvider).forShop(shopId);
  return buildStatement(opening: shop.openingBalance, closing: shop.receivable, transactions: txns);
}

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
