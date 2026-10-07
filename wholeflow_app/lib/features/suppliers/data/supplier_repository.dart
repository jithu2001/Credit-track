import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../domain/supplier.dart';

/// Suppliers. RLS returns them to the owner only.
class SupplierRepository {
  SupplierRepository(this._client);

  final SupabaseClient _client;

  /// Every active supplier of a company; searched and sorted on the phone.
  Future<List<Supplier>> all(String companyId) async {
    try {
      final rows = await fetchAll(
        (from, to) => _client
            .from('suppliers')
            .select(Supplier.columns)
            .eq('company_id', companyId)
            .isFilter('deleted_at', null)
            .order('name', ascending: true)
            .order('id', ascending: true)
            .range(from, to),
      );
      return rows.map(Supplier.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<Supplier> detail(String supplierId) async {
    try {
      final row = await _client
          .from('suppliers')
          .select(Supplier.columns)
          .eq('id', supplierId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) throw const AppFailure(FailureKind.notFound, 'This supplier is not available.');
      return Supplier.fromJson(row);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) => SupplierRepository(ref.watch(supabaseProvider)));
