import '../../../core/format.dart';
import '../../../core/money/money.dart';

/// A supplier ledger (Sundry Creditors by default) synced from Tally.
///
/// [payable] is signed the other way round from shops: positive means the
/// business owes the supplier (Cr), negative means an advance was paid (Dr).
class Supplier {
  const Supplier({
    required this.id,
    required this.companyId,
    required this.name,
    this.aliases = const [],
    this.ledgerGroup,
    this.phone,
    this.phones = const [],
    this.contactPerson,
    this.email,
    this.gstin,
    this.address,
    this.addressLines = const [],
    this.state,
    this.pincode,
    this.payable = Money.zero,
    this.openingPayable = Money.zero,
    this.syncedAt,
  });

  static const columns =
      'id,company_id,name,aliases,ledger_group,phone,phones,contact_person,email,gstin,address,address_lines,state,pincode,'
      'opening_balance_amount,opening_balance_type,payable,synced_at';

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    name: (json['name'] as String?) ?? '',
    aliases: parseStrings(json['aliases']),
    ledgerGroup: json['ledger_group'] as String?,
    phone: json['phone'] as String?,
    phones: parseStrings(json['phones']),
    contactPerson: json['contact_person'] as String?,
    email: json['email'] as String?,
    gstin: json['gstin'] as String?,
    address: json['address'] as String?,
    addressLines: parseStrings(json['address_lines']),
    state: json['state'] as String?,
    pincode: json['pincode'] as String?,
    payable: Money.parse(json['payable']),
    // Cr opening = we owed the supplier, the same sign as payable.
    openingPayable: -Money.fromSide(json['opening_balance_amount'], json['opening_balance_type'] as String?),
    syncedAt: json['synced_at'] == null ? null : DateTime.tryParse(json['synced_at'] as String),
  );

  final String id;
  final String companyId;
  final String name;
  final List<String> aliases;
  final String? ledgerGroup;
  final String? phone;
  final List<String> phones;
  final String? contactPerson;
  final String? email;
  final String? gstin;
  final String? address;
  final List<String> addressLines;
  final String? state;
  final String? pincode;
  final Money payable;
  final Money openingPayable;
  final DateTime? syncedAt;

  List<String> get allPhones {
    final out = <String>[];
    for (final p in [?phone, ...phones]) {
      final t = p.trim();
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }
    return out;
  }

  String? get fullAddress {
    final lines = addressLines.where((l) => l.trim().isNotEmpty).toList();
    final text = lines.isNotEmpty ? lines.join('\n') : (address ?? '');
    // Tally address lines often already end with the state and PIN code.
    final lower = text.toLowerCase();
    final tail = [
      state,
      pincode,
    ].where((s) => s != null && s.trim().isNotEmpty && !lower.contains(s.trim().toLowerCase())).join(' ');
    final all = [text.trim(), tail].where((s) => s.isNotEmpty).join('\n');
    return all.isEmpty ? null : all;
  }

  /// Case-insensitive match on name, aliases, phone and GSTIN.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        aliases.any((a) => a.toLowerCase().contains(q)) ||
        allPhones.any((p) => p.contains(q)) ||
        (gstin?.toLowerCase().contains(q) ?? false);
  }
}

enum PayableFilter {
  all('All'),
  owed('You owe'),
  advance('Advance paid'),
  settled('Settled');

  const PayableFilter(this.label);
  final String label;

  bool test(Supplier s) => switch (this) {
    PayableFilter.all => true,
    PayableFilter.owed => s.payable.isPositive,
    PayableFilter.advance => s.payable.isNegative,
    PayableFilter.settled => s.payable.isZero,
  };
}

enum SupplierSort {
  payableDesc('Amount you owe (high to low)'),
  name('Name (A–Z)');

  const SupplierSort(this.label);
  final String label;
}

List<Supplier> filterSuppliers(
  List<Supplier> all, {
  String query = '',
  PayableFilter filter = PayableFilter.all,
  SupplierSort sort = SupplierSort.payableDesc,
}) {
  int byName(Supplier a, Supplier b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final out = all.where((s) => filter.test(s) && s.matches(query)).toList();
  switch (sort) {
    case SupplierSort.payableDesc:
      out.sort((a, b) {
        final c = b.payable.compareTo(a.payable);
        return c != 0 ? c : byName(a, b);
      });
    case SupplierSort.name:
      out.sort(byName);
  }
  return out;
}

/// Sum of what the business owes (advances not netted off).
Money totalOwed(Iterable<Supplier> suppliers) =>
    suppliers.fold(Money.zero, (sum, s) => s.payable.isPositive ? sum + s.payable : sum);
