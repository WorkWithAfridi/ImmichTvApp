import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_protocol.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_service_io.dart';

void main() {
  late IoPhonePairingService service;

  setUp(() {
    service = IoPhonePairingService(addressProvider: () async => ['127.0.0.1']);
  });

  tearDown(() async {
    await service.dispose();
  });

  test('serves a local preview page and waits for TV approval', () async {
    final connection = await service.start();
    final client = HttpClient();
    addTearDown(client.close);

    final pageRequest = await client.getUrl(connection.manualUris.single);
    final pageResponse = await pageRequest.close();
    final page = await utf8.decoder.bind(pageResponse).join();
    expect(pageResponse.statusCode, HttpStatus.ok);
    expect(page, contains('Phone text entry is not enabled'));
    expect(
      pageResponse.headers.value('content-security-policy'),
      contains("script-src 'nonce-"),
    );

    final fragment = Uri(query: connection.qrUri.fragment).queryParameters;
    final pairResponse = await _post(
      client,
      connection.manualUris.single,
      '/api/pair',
      {'sessionId': fragment['session'], 'bootstrapToken': fragment['token']},
    );
    expect(pairResponse.statusCode, HttpStatus.ok);
    expect(service.snapshot?.phase, PairingPhase.approvalPending);

    service.approve();
    final statusResponse = await _post(
      client,
      connection.manualUris.single,
      '/api/status',
      {'sessionId': fragment['session']},
    );
    expect(statusResponse.statusCode, HttpStatus.ok);
    expect(jsonDecode(await utf8.decoder.bind(statusResponse).join()), {
      'phase': PairingPhase.active.name,
    });
  });

  test('rejects cross-origin pairing requests', () async {
    final connection = await service.start();
    final client = HttpClient();
    addTearDown(client.close);
    final fragment = Uri(query: connection.qrUri.fragment).queryParameters;
    final response = await _post(
      client,
      connection.manualUris.single,
      '/api/pair',
      {'sessionId': fragment['session'], 'bootstrapToken': fragment['token']},
      origin: 'http://attacker.example',
    );
    expect(response.statusCode, HttpStatus.forbidden);
    expect(service.snapshot?.phase, PairingPhase.waitingForPhone);
  });
}

Future<HttpClientResponse> _post(
  HttpClient client,
  Uri base,
  String path,
  Map<String, Object?> body, {
  String? origin,
}) async {
  final request = await client.postUrl(base.resolve(path));
  request.headers.contentType = ContentType.json;
  request.headers.set('Origin', origin ?? base.origin);
  request.write(jsonEncode(body));
  return request.close();
}
