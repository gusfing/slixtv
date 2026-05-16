import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'package:html/parser.dart' show parse;

class ResponseParser {
  static Map<String, dynamic> parseResponse(Response response) {
    try {
      final contentType = response.headers.value('content-type') ?? '';
      
      // 1. Map body
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      
      // 2. Handle known js=false or js=null values
      if (response.data == false || response.data == null || response.data == 'false') {
        return {'js': false};
      }

      String bodyString = response.data.toString();

      // 3. JSON
      if (contentType.contains('application/json') || contentType.contains('text/json')) {
        try {
          final decoded = json.decode(bodyString);
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          } else {
            return {'js': decoded};
          }
        } catch (_) {
          // Fallback to string handling
        }
      }

      // 4. XML
      if (contentType.contains('text/xml') || contentType.contains('application/xml') || bodyString.trim().startsWith('<?xml')) {
        try {
          final document = XmlDocument.parse(bodyString);
          // A very basic XML to JSON. Real stalker XMLs are usually simple
          // For Stalker portals, sometimes they return XML for errors
          return {'js': false, 'error': document.innerText};
        } catch (_) {
          // Fallback
        }
      }

      // 5. HTML / PHP Errors
      if (contentType.contains('text/html') || bodyString.trim().toLowerCase().startsWith('<!doctype html>') || bodyString.trim().toLowerCase().startsWith('<html')) {
        try {
          final document = parse(bodyString);
          
          // Try to extract JSON embedded in HTML if any
          final regex = RegExp(r'\{.*"js"\s*:.*\}', dotAll: true);
          final match = regex.firstMatch(bodyString);
          if (match != null) {
            try {
              final embeddedJson = json.decode(match.group(0)!);
              if (embeddedJson is Map) {
                return Map<String, dynamic>.from(embeddedJson);
              }
            } catch (_) {}
          }
          
          // Extract PHP error messages
          final bTags = document.getElementsByTagName('b');
          if (bTags.isNotEmpty) {
             final possibleError = document.body?.text ?? 'Unknown HTML error';
             return {'js': false, 'error': possibleError.trim()};
          }
        } catch (_) {}
      }

      // 6. Generic String Fallback
      try {
        final decoded = json.decode(bodyString);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        } else {
          return {'js': decoded};
        }
      } catch (_) {
        // If it's just a raw string that isn't JSON
        return {'js': false, 'raw': bodyString};
      }
    } catch (e) {
      // Complete parsing failure
      return {'js': false, 'error': e.toString()};
    }
  }
}
