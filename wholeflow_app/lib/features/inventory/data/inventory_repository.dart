import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
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

  /// Every active stock item of a company, sorted by name.
  Future<List<StockItem>> items(String companyId, {required bool withCosts}) async {
    try {
      final rows = await fetchAll((from, to) {
        var q = _client.from(_table(withCosts)).select(_columns(withCosts)).eq('company_id', companyId);
        // The view already leaves out deleted items.
        if (!withCosts) q = q.isFilter('deleted_at', null);
        return q.order('name', ascending: true).order(_idColumn(withCosts), ascending: true).range(from, to);
      });
      return rows.map(StockItem.fromJson).toList();
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
      return StockItem.fromJson(row);
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
