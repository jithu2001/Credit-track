import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/supplier.dart';

/// Suppliers from the WholeFlow app API (owner only).
class SupplierRepository {
  SupplierRepository(this._api);

  final ApiClient _api;

  /// Every active supplier of a company; searched and sorted on the phone.
  Future<List<Supplier>> all(String companyId) async {
    try {
      final body = await _api.get('suppliers', {'company': companyId});
      return [for (final r in (body['suppliers'] as List).cast<Map<String, dynamic>>()) Supplier.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<Supplier> detail(String supplierId) async {
    try {
      return Supplier.fromJson(await _api.get('suppliers/$supplierId'));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) => SupplierRepository(ref.watch(apiClientProvider)));
