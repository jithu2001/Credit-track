import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../domain/stock_item.dart';

class InventoryRepository {
  InventoryRepository(this._client);

  final SupabaseClient _client;

  /// Owners read `v_stock_items` (cost and last purchase); staff read
  /// `stock_items` and only ask for quantities. RLS shows staff a company's
  /// stock only when they are assigned to it.
  String _table(bool withCosts) => withCosts ? 'v_stock_items' : 'stock_items';
  String _columns(bool withCosts) => withCosts ? StockItem.ownerColumns : StockItem.staffColumns;
  String _idColumn(bool withCosts) => withCosts ? 'stock_item_id' : 'id';

  /// Every active stock item of a company, sorted by name, with the owner's
  /// minimum stock merged in.
  Future<List<StockItem>> items(String companyId, {required bool withCosts}) async {
    try {
      final (rows, mins) = await (
        fetchAll((from, to) {
          var q = _client.from(_table(withCosts)).select(_columns(withCosts)).eq('company_id', companyId);
          // The view already leaves out deleted items.
          if (!withCosts) q = q.isFilter('deleted_at', null);
          return q.order('name', ascending: true).order(_idColumn(withCosts), ascending: true).range(from, to);
        }),
        minimums(companyId),
      ).wait;
      return [
        for (final row in rows)
          if (StockItem.fromJson(row) case final item) item.withMinimum(mins[item.id]),
      ];
    } catch (e) {
      throw AppFailure.from(e is ParallelWaitError ? (e.errors.$1 ?? e.errors.$2 ?? e) : e);
    }
  }

  /// The owner's minimum stock per item id (`stock_minimums`).
  Future<Map<String, double>> minimums(String companyId) async {
    final rows = await fetchAll(
      (from, to) => _client
          .from('stock_minimums')
          .select('stock_item_id,min_qty')
          .eq('company_id', companyId)
          .order('stock_item_id', ascending: true)
          .range(from, to),
    );
    return {for (final r in rows) r['stock_item_id'] as String: parseQty(r['min_qty'])};
  }

  /// Sets [min] as the minimum stock of every item in [itemIds]; null or 0
  /// removes it. Owner only (the server refuses anyone else).
  Future<void> setMinimum(String companyId, Iterable<String> itemIds, double? min) async {
    try {
      await _client.rpc('set_stock_minimum', params: {'p_company': companyId, 'p_items': itemIds.toSet().toList(), 'p_min': min});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<StockItem> item(String itemId, {required bool withCosts}) async {
    try {
      var q = _client.from(_table(withCosts)).select(_columns(withCosts)).eq(_idColumn(withCosts), itemId);
      if (!withCosts) q = q.isFilter('deleted_at', null);
      final row = await q.maybeSingle();
      if (row == null) throw const AppFailure(FailureKind.notFound, 'This item is not available.');
      final min = await _client.from('stock_minimums').select('min_qty').eq('stock_item_id', itemId).maybeSingle();
      return StockItem.fromJson(row).withMinimum(min == null ? null : parseQty(min['min_qty']));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// The latest purchase bills containing [itemId]. Owner only: RLS returns
  /// nothing to staff.
  Future<List<ItemPurchase>> purchasesOf(String itemId, {int limit = 20}) async {
    try {
      final rows = await _client
          .from('purchases')
          .select('id,purchase_date,supplier_name,voucher_number,purchase_lines!inner(qty,unit,rate,amount)')
          .eq('purchase_lines.stock_item_id', itemId)
          .isFilter('deleted_at', null)
          .order('purchase_date', ascending: false)
          .order('tally_alter_id', ascending: false)
          .limit(limit);
      return rows.map(ItemPurchase.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) => InventoryRepository(ref.watch(supabaseProvider)));
