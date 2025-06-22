import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
// HTTP Request
import 'package:http/http.dart' as http;
// Shared Preferences
import 'package:shared_preferences/shared_preferences.dart';

class SpeedTestResult {
  final String domain;
  final double time; // milliseconds

  SpeedTestResult({
    required this.domain,
    required this.time,
  });

  Map<String, dynamic> toJson() {
    return {
      'domain': domain,
      'time': time,
    };
  }

  factory SpeedTestResult.fromJson(Map<String, dynamic> json) {
    return SpeedTestResult(
      domain: json['domain'] as String,
      time: (json['time'] as num).toDouble(),
    );
  }

  @override
  String toString() {
    return '{domain: $domain, time: $time}';
  }
}

class SpeedTestManager {
  static const String _storageKey = 'speed_test_results';
  static const String _testPath = '/test-img';
  static const int _maxTimeout = 30000;

  // 請求圖片
  Future<double> downloadImg(String domain) async {
    return await Isolate.run(() => _downloadImgInIsolate(domain));
  }

  //儲存結果
  Future<void> set(List<SpeedTestResult> results) async {
    try {
      results.sort((a, b) => a.time.compareTo(b.time));

      final jsonList = results.map((result) => result.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonString);

      log('Test results saved: $jsonString');
    } catch (e) {
      log('Save results error: $e');
    }
  }

  //取出結果
  Future<List<SpeedTestResult>> get() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .map((json) => SpeedTestResult.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      log('Get results error: $e');
      return [];
    }
  }

  Future<void> clearResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      log('Clear results error: $e');
    }
  }

  // 執行測數
  /// Runs the speed test in an isolate.
  ///
  /// [domains] is a list of domains to test.
  ///
  /// The function returns a JSON string containing the results. Each result is
  /// represented as a JSON object with the following keys:
  ///
  /// * `domain`: The domain that was tested.
  /// * `time`: The time taken to download the image, in milliseconds.
  ///
  /// The results are sorted by time in ascending order. If the download times
  /// out, the time is set to [_maxTimeout] milliseconds.
  Future<String> _runSpeedTestInIsolate(List<String> domains) async {
    final results = <SpeedTestResult>[];

    for (final domain in domains) {
      final time = await downloadImg(domain);

      if (time != double.maxFinite) {
        results.add(SpeedTestResult(domain: domain, time: time));
      } else {
        results.add(SpeedTestResult(
          domain: domain,
          time: _maxTimeout.toDouble(),
        ));
      }
    }

    results.sort((a, b) => a.time.compareTo(b.time));

    final jsonList = results.map((result) => result.toJson()).toList();
    return jsonEncode(jsonList);
  }

  static Future<double> _downloadImgInIsolate(String domain) async {
    final url = 'https://$domain$_testPath';
    // For test
    // final url = 'https://picsum.photos/200/300';

    final stopwatch = Stopwatch()..start();

    try {
      final client = http.Client();

      final response = await client
          .get(
        Uri.parse(url),
      )
          .timeout(
        const Duration(milliseconds: _maxTimeout),
        onTimeout: () {
          throw TimeoutException('Timeout', const Duration(seconds: 30));
        },
      );

      stopwatch.stop();
      client.close();

      if (response.statusCode == 200) {
        final _ = response.bodyBytes;
        return stopwatch.elapsedMilliseconds.toDouble();
      } else {
        throw HttpException(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      stopwatch.stop();
      return double.maxFinite;
    }
  }

  Future<List<SpeedTestResult>> runSpeedTest(List<String> domains) async {
    clearResults();
    final resultsJson =
        await Isolate.run(() => _runSpeedTestInIsolate(domains));

    final jsonList = jsonDecode(resultsJson) as List;
    final results = jsonList
        .map((json) => SpeedTestResult.fromJson(json as Map<String, dynamic>))
        .toList();

    log('Test results: $resultsJson');

    if (results.isNotEmpty) {
      await set(results);
    }

    return results;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final speedTest = SpeedTestManager();
  const List<String> domains = ['a.com', 'b.com', 'c.com'];

  final results = await speedTest.runSpeedTest(domains);

  final savedResults = await speedTest.get();
  print(savedResults);
}
