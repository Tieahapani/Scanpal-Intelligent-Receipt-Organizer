import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';          // for debugPrint
import 'package:http/http.dart' as http;

import 'receipt.dart';
import 'env.dart';

class APIService {
  final String baseUrl;

  APIService({String? baseUrl}) : baseUrl = baseUrl ?? Env.baseUrl {
    debugPrint('APIService baseUrl = $baseUrl');   // prove which URL is used
  }

  Future<Receipt> uploadReceipt(File image) async {
    final uri = Uri.parse('$baseUrl/expense');
    debugPrint('POST $uri  (file=${image.path})');

    // Multipart with a client-side timeout so you see errors faster
    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', image.path));

    http.StreamedResponse streamed;
    try {
      streamed = await req.send(); 
    } on SocketException catch (e) {
      // connection problems before request reaches server
      debugPrint('SocketException while sending: $e');
      rethrow;
    } on HttpException catch (e) {
      debugPrint('HttpException while sending: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('Timeout while sending: $e');
      rethrow;
    }  

    final res = await http.Response.fromStream(streamed);
    debugPrint('RESP ${res.statusCode}: ${res.body}');

    if (res.statusCode != 200) {
      throw Exception('Expense parse failed: ${res.statusCode} ${res.reasonPhrase}\n${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final receiptMap = data['receipt'] ?? data; // support both shapes
    return Receipt.fromMap(Map<String, dynamic>.from(receiptMap));
  }
}
