import 'package:flutter/foundation.dart';

import '../../services/update_service.dart';

/// Holds the result of the one update check this launch performs.
///
/// Deliberately has no bearing on the reading: it never blocks, never
/// retries, and a failure simply leaves [available] null so the banner is
/// not shown. Dismissal lasts for the session only -- no storage dependency
/// and no persisted state, matching the rest of the app.
class UpdateController extends ChangeNotifier {
  UpdateController({UpdateService? service}) : _service = service ?? UpdateService();

  final UpdateService _service;
  UpdateInfo? _available;
  bool _checked = false;
  final Set<String> _dismissed = <String>{};

  /// The update to offer, or null when there is nothing to show.
  UpdateInfo? get available {
    final info = _available;
    if (info == null || _dismissed.contains(info.version)) return null;
    return info;
  }

  bool get hasChecked => _checked;

  /// Runs at most once per launch. Safe to call from initState.
  Future<void> checkOnce() async {
    if (_checked) return;
    _checked = true;
    final info = await _service.check();
    if (info == null) return;
    _available = info;
    notifyListeners();
  }

  void dismiss() {
    final info = _available;
    if (info == null) return;
    _dismissed.add(info.version);
    notifyListeners();
  }
}
