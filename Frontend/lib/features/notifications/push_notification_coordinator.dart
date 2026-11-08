import 'dart:convert';
import '../auth/data/session_manager.dart';
import '../sighting/data/sightings_service.dart';
import '../report/data/reports_service.dart';

typedef PushHistoryLoader = Future<Map<String, dynamic>> Function(int reportId);

class PushNotice {
  const PushNotice(
    this.notificationId,
    this.reportId,
    this.sightingId,
    this.ownerId,
  );
  final int notificationId;
  final int reportId;
  final int sightingId;
  final int ownerId;

  static PushNotice? parse(Map<String, dynamic> data) {
    int? id(String name) {
      final text = data[name]?.toString() ?? '';
      if (!RegExp(r'^[1-9]\d*$').hasMatch(text)) return null;
      final value = int.tryParse(text);
      return value != null && value <= 2147483647 ? value : null;
    }

    if (data['type'] != 'AVISTAMIENTO_VINCULADO') return null;
    final notification = id('notificationId'),
        report = id('reportId'),
        owner = id('ownerId');
    if (notification == null ||
        report == null ||
        owner == null ||
        id('sightingId') == null) {
      return null;
    }
    return PushNotice(notification, report, id('sightingId')!, owner);
  }
}

// Account hints only control presentation. The private report request still
// enforces ownership in PostgreSQL before any detail can be opened.
class PushNotificationCoordinator {
  PushNotificationCoordinator({
    required this.session,
    required this.loadReport,
    required this.onOpen,
    required this.onForeground,
    this.loadHistory = _defaultLoadHistory,
    this.onUnavailable,
  }) {
    _logout = session.logoutGeneration;
    session.addListener(_sessionChanged);
  }
  final SessionManager session;
  final Future<OwnReportDetails> Function(int) loadReport;
  final PushHistoryLoader loadHistory;
  final void Function(int, int) onOpen;
  final void Function(PushNotice, void Function()) onForeground;
  final void Function()? onUnavailable;
  final Set<int> _shown = {}, _opened = {};
  PushNotice? _queued;
  late int _logout;
  bool _disposed = false;
  Future<void>? _opening;
  Future<void> get pending => _opening ?? Future<void>.value();

  static Future<Map<String, dynamic>> _defaultLoadHistory(int reportId) =>
      SightingsService.getReportHistory(reportId: reportId);

  int? get _userId {
    if (!session.isAuthenticated) return null;
    try {
      final part = session.accessToken!.split('.')[1];
      final data = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(part))),
      );
      return int.tryParse(data['sub'].toString());
    } catch (_) {
      return null;
    }
  }

  void foreground(Map<String, dynamic> data, {required bool allowed}) {
    final notice = PushNotice.parse(data);
    if (_disposed ||
        !allowed ||
        notice == null ||
        notice.ownerId != _userId ||
        !_remember(_shown, notice.notificationId)) {
      return;
    }
    onForeground(notice, () => tap(data));
  }

  void tap(Map<String, dynamic> data) {
    if (_disposed) return;
    final notice = PushNotice.parse(data);
    if (notice == null || _opened.contains(notice.notificationId)) return;
    _queued = notice;
    _sessionChanged();
  }

  void _sessionChanged() {
    if (_disposed) return;
    if (_logout != session.logoutGeneration) {
      _logout = session.logoutGeneration;
      if (_queued != null && _queued!.ownerId != _userId) _queued = null;
    }
    if (!session.isAuthenticated ||
        _queued == null ||
        _queued!.ownerId != _userId ||
        _opening != null) {
      return;
    }
    _opening = _openQueued().whenComplete(() {
      _opening = null;
      if (_queued != null && !_disposed) _sessionChanged();
    });
  }

  Future<void> _openQueued() async {
    final notice = _queued!;
    _queued = null;
    if (notice.ownerId != _userId || _opened.contains(notice.notificationId)) {
      return;
    }
    final generation = session.authenticatedSessionGeneration;
    try {
      final results = await Future.wait([
        loadReport(notice.reportId),
        loadHistory(notice.reportId),
      ]);
      final history = results[1] as Map<String, dynamic>;
      final sightings = history['sightings'] as List<dynamic>? ?? const [];
      final exists = sightings.any(
        (item) =>
            item is Map &&
            int.tryParse(item['id'].toString()) == notice.sightingId,
      );
      if (_disposed ||
          generation != session.authenticatedSessionGeneration ||
          notice.ownerId != _userId ||
          !exists) {
        return;
      }
      _remember(_opened, notice.notificationId);
      onOpen(notice.reportId, notice.sightingId);
    } catch (_) {
      if (!_disposed && generation == session.authenticatedSessionGeneration) {
        onUnavailable?.call();
      }
    }
  }

  bool _remember(Set<int> ids, int id) {
    if (!ids.add(id)) return false;
    if (ids.length > 100) ids.remove(ids.first);
    return true;
  }

  void dispose() {
    _disposed = true;
    _queued = null;
    session.removeListener(_sessionChanged);
  }
}
