import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supplier_repository.dart';
import '../domain/supplier.dart';

/// Every supplier of a company (owner only).
final suppliersProvider = FutureProvider.autoDispose.family<List<Supplier>, String>(
  (ref, companyId) => ref.watch(supplierRepositoryProvider).all(companyId),
);

final supplierDetailProvider = FutureProvider.autoDispose.family<Supplier, String>(
  (ref, supplierId) => ref.watch(supplierRepositoryProvider).detail(supplierId),
);
