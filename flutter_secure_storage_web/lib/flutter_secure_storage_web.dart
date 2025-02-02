library flutter_secure_storage_web;

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:js_util' as js_util;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import './src/subtle.dart' as crypto;

class FlutterSecureStorageWeb extends FlutterSecureStoragePlatform {
  static const publicKey = 'publicKey';

  static void registerWith(Registrar registrar) {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWeb();
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) =>
      Future.value(html.window.localStorage
          .containsKey("${options[publicKey]!}.$key"));

  @override
  Future<String?> delete({
    required String key,
    required Map<String, String> options,
  }) =>
      Future.value(html.window.localStorage.remove("${options[publicKey]!}.$key"));

  @override
  Future<void> deleteAll({
    required Map<String, String> options,
  }) =>
      Future.sync(
          () => html.window.localStorage.removeWhere((key, value) => true));

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    final value = html.window.localStorage["${options[publicKey]!}.$key"];

    return await _decryptValue(value, options);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    final map = <String, String>{};
    final prefix = "${options[publicKey]!}.";
    for (int j = 0; j < html.window.localStorage.length; j++) {
      final entry = html.window.localStorage.entries.elementAt(j);
      if (!entry.key.startsWith(prefix)) {
        continue;
      }

      final value = await _decryptValue(entry.value, options);

      if (value == null) {
        continue;
      }

      map[entry.key.substring(prefix.length)] = value;
    }

    return map;
  }

  crypto.Algorithm _getAlgorithm(Uint8List iv) =>
      crypto.Algorithm(name: 'AES-GCM', length: 256, iv: iv);

  Future<html.CryptoKey> _getEncryptionKey(
      crypto.Algorithm algorithm, Map<String, String> options) async {
    late html.CryptoKey encryptionKey;
    final key = options[publicKey]!;

    if (html.window.localStorage.containsKey(key)) {
      final jwk = base64Decode(html.window.localStorage[key]!);

      encryptionKey = await js_util.promiseToFuture<html.CryptoKey>(
        crypto.importKey("raw", jwk, algorithm, false, ["encrypt", "decrypt"]),
      );
    } else {
      //final crypto.getRandomValues(Uint8List(256));

      encryptionKey = await js_util.promiseToFuture<html.CryptoKey>(
        crypto.generateKey(algorithm, true, ["encrypt", "decrypt"]),
      );

      final jsonWebKey = await js_util
          .promiseToFuture<ByteBuffer>(crypto.exportKey("raw", encryptionKey));
      html.window.localStorage[key] = base64Encode(jsonWebKey.asUint8List());
    }

    return encryptionKey;
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    final iv =
        html.window.crypto!.getRandomValues(Uint8List(12)).buffer.asUint8List();

    final algorithm = _getAlgorithm(iv);

    final encryptionKey = await _getEncryptionKey(algorithm, options);

    final encryptedContent = await js_util.promiseToFuture<ByteBuffer>(
      crypto.encrypt(
        algorithm,
        encryptionKey,
        Uint8List.fromList(
          utf8.encode(value),
        ),
      ),
    );

    final encoded =
        "${base64Encode(iv)}.${base64Encode(encryptedContent.asUint8List())}";

    html.window.localStorage["${options[publicKey]!}.$key"] = encoded;
  }

  Future<String?> _decryptValue(
    String? cypherText,
    Map<String, String> options,
  ) async {
    if (cypherText == null) {
      return null;
    }

    final parts = cypherText.split(".");

    final iv = base64Decode(parts[0]);
    final algorithm = _getAlgorithm(iv);

    final decryptionKey = await _getEncryptionKey(algorithm, options);

    final value = base64Decode(parts[1]);

    final decryptedContent = await js_util.promiseToFuture<ByteBuffer>(
      crypto.decrypt(
        _getAlgorithm(iv),
        decryptionKey,
        Uint8List.fromList(value),
      ),
    );

    final plainText = utf8.decode(decryptedContent.asUint8List());

    return plainText;
  }
}
