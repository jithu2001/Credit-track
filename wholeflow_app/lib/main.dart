import 'bootstrap.dart';
import 'owner_app.dart';

/// Default entry point (`flutter run` without `-t`): WholeFlow Owner.
Future<void> main() => bootstrapWholeFlow(appWidget: const WholeFlowOwnerApp(), title: 'WholeFlow Owner', flavor: 'owner');
