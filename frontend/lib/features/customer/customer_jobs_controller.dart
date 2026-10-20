import 'package:flutter/foundation.dart';

import '../../models/job.dart';
import '../../providers/marketplace_provider.dart';

/// Load state of the customer's orders for the redesigned shell. The list
/// itself stays in [MarketplaceProvider.customerJobs]; this only tracks
/// loading / error for Home and My Orders, because the provider shares one
/// `isLoading` / `error` between services, booking and jobs.
class CustomerJobsController extends ChangeNotifier {
  CustomerJobsController(this._marketplace, this._token);

  final MarketplaceProvider _marketplace;
  final String? Function() _token;

  bool _loading = false;
  bool _loaded = false;
  String? _error;
  int _generation = 0;

  bool get loading => _loading;

  /// True once a fetch has finished (successfully or not).
  bool get loaded => _loaded;
  String? get error => _error;
  List<Job> get jobs => _marketplace.customerJobs;

  Future<void> refresh() async {
    final token = _token();
    final gen = ++_generation;
    _loading = true;
    _error = null;
    notifyListeners();
    await _marketplace.fetchCustomerJobs(token);
    if (gen != _generation) return; // a newer refresh owns the state
    _error = _marketplace.error;
    _loading = false;
    _loaded = true;
    notifyListeners();
  }
}
