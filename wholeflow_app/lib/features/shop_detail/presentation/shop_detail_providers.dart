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
