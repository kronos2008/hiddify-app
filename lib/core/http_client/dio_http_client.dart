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
  DioHttpClient({required Duration timeout, required this.userAgent, required bool debug}) {
    for (var mode in ["proxy", "direct", "both"]) {
      _dio[mode] = Dio(
        BaseOptions(
          connectTimeout: timeout,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          headers: {"User-Agent": userAgent},
        ),
      );
      _dio[mode]!.interceptors.add(
        RetryInterceptor(
          dio: _dio[mode]!,
          retryDelays: [
            const Duration(seconds: 1),
            if (mode != "proxy") ...[const Duration(seconds: 2), const Duration(seconds: 3)],
          ],
        ),
      );

      _dio[mode]!.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (url) {
            if (mode == "proxy") {
              return "PROXY localhost:$port";
            } else if (mode == "direct") {
              return "DIRECT";
            } else {
              return "PROXY localhost:$port; DIRECT";
            }
          };
          return client;
        },
      );
    }

    if (debug) {
      // _dio.interceptors.add(LoggyDioInterceptor(requestHeader: true));
    }
  }

  int port = 0;

  String userAgent;

  Future<bool> isPortOpen(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      await socket.close();
      return true;
    } on SocketException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  void setProxyPort(int port) {
    this.port = port;
    loggy.debug("setting proxy port: [$port]");
  }

  Future<Map<String, String>> _deviceHeaders() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        final hwid = md5.convert(utf8.encode(info.id)).toString();
        return {
          'hwid': hwid,
          'device_os': 'android',
          'device_model': info.model,
          'os_version': info.version.release,
        };
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final hwid = md5.convert(utf8.encode(info.identifierForVendor ?? 'unknown')).toString();
        return {
          'hwid': hwid,
          'device_os': 'ios',
          'device_model': info.model,
          'os_version': info.systemVersion,
        };
      }
    } catch (_) {}
    return {};
  }

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

    return dio.get<T>(
      url,
      cancelToken: cancelToken,
      options: _options(url, userAgent: userAgent, credentials: credentials),
    );
  }

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

    final deviceHeaders = await _deviceHeaders();

    return dio.download(
      url,
      path,
      cancelToken: cancelToken,
      options: _options(url, userAgent: userAgent, credentials: credentials, extraHeaders: deviceHeaders),
    );
  }

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
