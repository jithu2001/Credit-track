import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_json.dart';

part 'shop.freezed.dart';
part 'shop.g.dart';

Object? _readShopId(Map<dynamic, dynamic> json, String key) => json['shop_id'] ?? json['id'];

// `site_name` from the view, or the embedded `sites(name)` from the table.
Object? _readSiteName(Map<dynamic, dynamic> json, String key) => json['site_name'] ?? (json['sites'] as Map?)?['name'];

/// One line of a shop list: from `shops` or `v_shop_outstanding`.
@freezed
abstract class ShopSummary with _$ShopSummary {
  const factory ShopSummary({
    @JsonKey(readValue: _readShopId) required String id,
    required String name,
    String? area,
    String? phone,
    @MoneyConverter() @Default(Money.zero) Money receivable,
    String? siteId,
    @JsonKey(readValue: _readSiteName) String? siteName,
  }) = _ShopSummary;

  factory ShopSummary.fromJson(Map<String, dynamic> json) => _$ShopSummaryFromJson(json);

  static const shopColumns = 'id,name,area,phone,receivable,site_id,sites(name)';
  static const viewColumns = 'shop_id,name,area,phone,receivable,site_id,site_name';
}

/// Everything the shop detail screen shows.
@freezed
abstract class ShopDetail with _$ShopDetail {
  const ShopDetail._();

  const factory ShopDetail({
    required String id,
    required String companyId,
    required String name,
    String? area,
    String? phone,
    @Default(<String>[]) List<String> phones,
    String? phoneSource,
    String? contactPerson,
    String? email,
    String? gstin,
    String? address,
    @Default(<String>[]) List<String> addressLines,
    String? state,
    String? pincode,
    @MoneyConverter() @Default(Money.zero) Money openingBalanceAmount,
    @Default('') String openingBalanceType,
    @MoneyConverter() @Default(Money.zero) Money receivable,
    DateTime? syncedAt,
    String? siteId,
    @JsonKey(readValue: _readSiteName) String? siteName,
  }) = _ShopDetail;

  factory ShopDetail.fromJson(Map<String, dynamic> json) => _$ShopDetailFromJson(json);

  static const columns =
      'id,company_id,name,area,phone,phones,phone_source,contact_person,email,gstin,address,'
      'address_lines,state,pincode,opening_balance_amount,opening_balance_type,receivable,synced_at,site_id,sites(name)';

  /// Signed like `receivable`: Dr opening balance is positive.
  Money get openingBalance => openingBalanceType == 'CR' ? -openingBalanceAmount.abs() : openingBalanceAmount.abs();

  /// Primary phone first, then the rest, without duplicates.
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
}

enum BalanceFilter {
  all('All'),
  owes('Owes us'),
  credit('In credit'),
  settled('Settled');

  const BalanceFilter(this.label);
  final String label;
}

enum ShopSort {
  balanceDesc('Balance: high to low'),
  balanceAsc('Balance: low to high'),
  name('Name');

  const ShopSort(this.label);
  final String label;
}

/// Search, filter and sort of the shop list. [siteIds] may hold [noSite]
/// for shops that are in no site.
@freezed
abstract class ShopFilter with _$ShopFilter {
  const factory ShopFilter({
    @Default('') String query,
    @Default(BalanceFilter.all) BalanceFilter balance,
    @Default(<String>{}) Set<String> siteIds,
    @Default(ShopSort.balanceDesc) ShopSort sort,
  }) = _ShopFilter;

  static const noSite = 'no-site';
}
