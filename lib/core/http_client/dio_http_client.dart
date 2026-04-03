import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';

import 'package:hiddify/utils/custom_loggers.dart';

class DioHttpClient with InfraLogger {
  final Map<String, Dio> _dio = {};

  int port = 0;
  String userAgent;

  DioHttpClient({
    required Duration timeout,
    required this.userAgent,
    required bool debug,
  }) {
    for (var mode in ["proxy", "direct", "both"]) {
      final dio = Dio(
        BaseOptions(
          connectTimeout: timeout,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          headers: {"User-Agent": userAgent},
        ),
      );

      dio.interceptors.add(
        RetryInterceptor(
          dio: dio,
          retries: 3,
          retryDelays: const [
            Duration(seconds: 1),
            Duration(seconds: 2),
            Duration(seconds: 3),
          ],
        ),
      );

      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();

          client.findProxy = (url) {
            if (mode == "proxy") {
              return "PROXY 127.0.0.1:$port";
            } else if (mode == "direct") {
              return "DIRECT";
            } else {
              return "PROXY 127.0.0.1:$port; DIRECT";
            }
          };

          client.badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;

          return client;
        },
      );

      _dio[mode] = dio;
    }
  }

  // ========================
  // 🔌 Проверка порта
  // ========================

  Future<bool> isPortOpen(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  void setProxyPort(int port) {
    this.port = port;
    loggy.debug("Proxy port set: $port");
  }

  // ========================
  // 📱 DEVICE HEADERS (ФИКС)
  // ========================

  Future<Map<String, String>> _deviceHeaders() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;

        final raw = "${android.id}-${android.model}-${android.version.sdkInt}";
        final hwid = md5.convert(utf8.encode(raw)).toString();

        return {
          'hwid': hwid,
          'device_os': 'android',
          'device_model': android.model ?? 'unknown',
          'os_version': android.version.release ?? 'unknown',
        };
      }

      if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;

        final raw =
            "${ios.identifierForVendor}-${ios.model}-${ios.systemVersion}";
        final hwid = md5.convert(utf8.encode(raw)).toString();

        return {
          'hwid': hwid,
          'device_os': 'ios',
          'device_model': ios.model ?? 'unknown',
          'os_version': ios.systemVersion ?? 'unknown',
        };
      }
    } catch (e) {
      loggy.error("Device header error: $e");
    }

    return {
      'hwid': 'unknown',
      'device_os': Platform.operatingSystem,
      'device_model': 'unknown',
      'os_version': Platform.operatingSystemVersion,
    };
  }

  // ========================
  // 🌐 GET
  // ========================

  Future<Response<T>> get<T>(
    String url, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
  }) async {
    final mode = proxyOnly
        ? "proxy"
        : await isPortOpen("127.0.0.1", port)
            ? "both"
            : "direct";

    final dio = _dio[mode]!;

    final headers = await _deviceHeaders();

    return dio.get<T>(
      url,
      cancelToken: cancelToken,
      options: _options(
        url,
        userAgent: userAgent,
        credentials: credentials,
        extraHeaders: headers,
      ),
    );
  }

  // ========================
  // ⬇️ DOWNLOAD
  // ========================

  Future<Response> download(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
  }) async {
    final mode = proxyOnly
        ? "proxy"
        : await isPortOpen("127.0.0.1", port)
            ? "both"
            : "direct";

    final dio = _dio[mode]!;

    final headers = await _deviceHeaders();

    return dio.download(
      url,
      path,
      cancelToken: cancelToken,
      options: _options(
        url,
        userAgent: userAgent,
        credentials: credentials,
        extraHeaders: headers,
      ),
    );
  }

  // ========================
  // ⚙️ OPTIONS
  // ========================

  Options _options(
    String url, {
    String? userAgent,
    ({String username, String password})? credentials,
    Map<String, String> extraHeaders = const {},
  }) {
    final uri = Uri.parse(url);

    String? userInfo;

    if (credentials != null) {
      userInfo = "${credentials.username}:${credentials.password}";
    } else if (uri.userInfo.isNotEmpty) {
      userInfo = uri.userInfo;
    }

    String? basicAuth;

    if (userInfo != null) {
      basicAuth = "Basic ${base64.encode(utf8.encode(userInfo))}";
    }

    return Options(
      headers: {
        if (userAgent != null) "User-Agent": userAgent,
        if (basicAuth != null) "authorization": basicAuth,
        ...extraHeaders,
      },
    );
  }
}
