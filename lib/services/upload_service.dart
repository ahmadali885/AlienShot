import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Uploads images anonymously to catbox.moe and returns the public URL.
///
/// No API key required. Swap this out for your own backend / S3 bucket /
/// Imgur client id if you need private or expiring links.
class UploadService {
  static final _endpoint = Uri.parse('https://catbox.moe/user/api.php');

  Future<String> uploadPng(Uint8List bytes) async {
    final request = http.MultipartRequest('POST', _endpoint)
      ..fields['reqtype'] = 'fileupload'
      ..files.add(
        http.MultipartFile.fromBytes(
          'fileToUpload',
          bytes,
          filename: 'alienshot_${DateTime.now().millisecondsSinceEpoch}.png',
        ),
      );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200 || !response.body.trim().startsWith('http')) {
      throw Exception('Upload failed (${response.statusCode}): ${response.body}');
    }

    return response.body.trim();
  }
}

final uploadService = UploadService();
