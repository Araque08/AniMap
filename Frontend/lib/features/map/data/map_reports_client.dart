import 'package:http/http.dart' as http;

import '../../auth/data/authenticated_http_client.dart';

class MapReportsClient {
  final AuthenticatedHttpClient _client;

  MapReportsClient({AuthenticatedHttpClient? client})
    : _client = client ?? AuthenticatedHttpClient.instance;

  Future<http.Response> getReports(Uri url) {
    return _client.get(url, optionalAuthentication: true);
  }
}
