import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ScienceSignalApp());
}

class ScienceSignalApp extends StatelessWidget {
  const ScienceSignalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Science Signal',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const ScienceQuizScreen(),
    );
  }
}

class ScienceQuestion {
  const ScienceQuestion({required this.text, required this.correctAnswer});

  final String text;
  final String correctAnswer;

  factory ScienceQuestion.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['question'] is! String ||
        value['correct_answer'] is! String ||
        value['incorrect_answers'] is! List) {
      throw const FormatException('Invalid question data.');
    }

    final text = Uri.decodeComponent(value['question'] as String);
    final correctAnswer = Uri.decodeComponent(
      value['correct_answer'] as String,
    );
    final incorrectAnswers = value['incorrect_answers'] as List;
    if (text.trim().isEmpty ||
        (correctAnswer != 'True' && correctAnswer != 'False') ||
        incorrectAnswers.length != 1 ||
        incorrectAnswers.first is! String) {
      throw const FormatException('Invalid true-or-false question.');
    }
    final incorrectAnswer = Uri.decodeComponent(
      incorrectAnswers.first as String,
    );
    if ((incorrectAnswer != 'True' && incorrectAnswer != 'False') ||
        incorrectAnswer == correctAnswer) {
      throw const FormatException('Invalid true-or-false answers.');
    }
    return ScienceQuestion(text: text, correctAnswer: correctAnswer);
  }
}

class ScienceQuizScreen extends StatefulWidget {
  const ScienceQuizScreen({super.key});

  @override
  State<ScienceQuizScreen> createState() => _ScienceQuizScreenState();
}

class _ScienceQuizScreenState extends State<ScienceQuizScreen> {
  static final _questionUri = Uri.https('opentdb.com', '/api.php', {
    'amount': '5',
    'category': '17',
    'difficulty': 'medium',
    'type': 'boolean',
    'encode': 'url3986',
  });

  List<ScienceQuestion> _questions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _loading = true;
      _error = null;
      _questions = [];
    });

    try {
      final response = await http
          .get(_questionUri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw FormatException('Server returned HTTP ${response.statusCode}.');
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['response_code'] != 0) {
        throw const FormatException('The trivia API did not return questions.');
      }
      final results = data['results'];
      if (results is! List || results.length != 5) {
        throw const FormatException('Expected five trivia questions.');
      }
      final questions = results.map(ScienceQuestion.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _loading = false;
      });
    } on TimeoutException {
      _showError('The request timed out. Please try again.');
    } on http.ClientException catch (error) {
      _showError('The request failed: ${error.message}');
    } on FormatException catch (error) {
      _showError('Could not load questions: ${error.message}');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Science Signal')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _loadQuestions,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('First question preview'),
                    const SizedBox(height: 12),
                    Text(_questions.first.text, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    const Text(
                      'Implement the quiz round, results review, and score submission.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
