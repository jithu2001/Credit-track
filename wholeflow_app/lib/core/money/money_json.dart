import 'package:json_annotation/json_annotation.dart';

import 'money.dart';

/// json_serializable converter for PostgREST `numeric` columns.
class MoneyConverter implements JsonConverter<Money, Object?> {
  const MoneyConverter();

  @override
  Money fromJson(Object? json) => Money.parse(json);

  @override
  Object? toJson(Money object) => object.paise / 100;
}
