import 'package:dio/dio.dart';

class CobaltException implements Exception {
  final String message;

  const CobaltException(this.message);

  @override
  String toString() => message;
}

class CobaltDownload {
  final String url;
  final String? filename;

  const CobaltDownload({required this.url, this.filename});
}

class CobaltService {
  static const String _configuredApiUrl = String.fromEnvironment(
    'COBALT_API_URL',
    defaultValue: 'http://127.0.0.1:9000',
  );

  final Dio _dio;
  final String apiUrl;

  CobaltService({Dio? dio, String apiUrl = _configuredApiUrl})
      : _dio = dio ?? Dio(),
        apiUrl = apiUrl.replaceFirst(RegExp(r'/+$'), '');

  Future<CobaltDownload> getHighestQualityVideo(String sourceUrl) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$apiUrl/',
        data: {
          'url': sourceUrl,
          'downloadMode': 'auto',
          'videoQuality': 'max',
          'allowH265': true,
          'filenameStyle': 'basic',
          'localProcessing': 'disabled',
        },
        options: Options(
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );

      final data = response.data;
      if (data == null) {
        throw const CobaltException('Cobalt devolvió una respuesta vacía');
      }

      final status = data['status']?.toString();
      if (status == 'redirect' || status == 'tunnel') {
        final downloadUrl = data['url']?.toString();
        if (downloadUrl == null || downloadUrl.isEmpty) {
          throw const CobaltException(
            'Cobalt no devolvió una URL de descarga',
          );
        }
        return CobaltDownload(
          url: downloadUrl,
          filename: data['filename']?.toString(),
        );
      }

      if (status == 'error') {
        final error = data['error'];
        final code = error is Map ? error['code']?.toString() : null;
        throw CobaltException(
          code == null ? 'Cobalt no pudo procesar el video' : 'Cobalt: $code',
        );
      }

      throw CobaltException(
        'Respuesta de Cobalt no compatible: ${status ?? 'desconocida'}',
      );
    } on DioException catch (error) {
      throw CobaltException(
        'No se pudo conectar con Cobalt (${error.type.name})',
      );
    }
  }
}
