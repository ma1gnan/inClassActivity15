import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const ScienceSignalApp());

class ScienceSignalApp extends StatelessWidget {
  const ScienceSignalApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Science Signal',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const ScienceQuizScreen(),
  );
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
    final correct = Uri.decodeComponent(value['correct_answer'] as String);
    final incorrect = value['incorrect_answers'] as List;
    if (text.trim().isEmpty ||
        (correct != 'True' && correct != 'False') ||
        incorrect.length != 1 ||
        incorrect.first is! String) {
      throw const FormatException('Invalid true-or-false question.');
    }
    final wrong = Uri.decodeComponent(incorrect.first as String);
    if ((wrong != 'True' && wrong != 'False') || wrong == correct) {
      throw const FormatException('Invalid true-or-false answers.');
    }
    return ScienceQuestion(text: text, correctAnswer: correct);
  }
}

class ScienceQuizScreen extends StatefulWidget {
  const ScienceQuizScreen({super.key});

  @override
  State<ScienceQuizScreen> createState() => _ScienceQuizScreenState();
}

class _ScienceQuizScreenState extends State<ScienceQuizScreen> {
  static final Uri _questionUri = Uri.https('opentdb.com', '/api.php', {
    'amount': '5',
    'category': '17',
    'difficulty': 'medium',
    'type': 'boolean',
    'encode': 'url3986',
  });

  List<ScienceQuestion> _questions = [];
  final List<String> _userAnswers = [];
  bool _loading = true;
  String? _error;
  int _currentQuestionIndex = 0;
  int _score = 0;
  String? _selectedAnswer;
  bool _quizFinished = false;
  bool _submitting = false;
  bool _simulatedSubmissionComplete = false;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    final requestVersion = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
      _questions = [];
      _userAnswers.clear();
      _currentQuestionIndex = 0;
      _score = 0;
      _selectedAnswer = null;
      _quizFinished = false;
      _submitting = false;
      _simulatedSubmissionComplete = false;
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
        throw FormatException(
          'The trivia API returned an unsuccessful response: '
          '${data is Map ? data['response_code'] : 'invalid data'}.',
        );
      }
      final results = data['results'];
      if (results is! List || results.length != 5) {
        throw const FormatException('Expected exactly five trivia questions.');
      }
      final questions = results.map(ScienceQuestion.fromJson).toList();
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _questions = questions;
        _loading = false;
      });
    } on TimeoutException {
      _showError('The request timed out. Please try again.', requestVersion);
    } on http.ClientException catch (error) {
      _showError('Network request failed: ${error.message}', requestVersion);
    } on FormatException catch (error) {
      _showError('Could not load questions: ${error.message}', requestVersion);
    } catch (_) {
      _showError(
        'Something went wrong while loading questions.',
        requestVersion,
      );
    }
  }

  void _showError(String message, int requestVersion) {
    if (!mounted || requestVersion != _requestVersion) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  void _selectAnswer(String answer) {
    if (_loading ||
        _error != null ||
        _quizFinished ||
        _selectedAnswer != null ||
        _currentQuestionIndex >= _questions.length) {
      return;
    }
    final question = _questions[_currentQuestionIndex];
    setState(() {
      _selectedAnswer = answer;
      _userAnswers.add(answer);
      if (answer == question.correctAnswer) _score++;
    });
  }

  void _nextQuestion() {
    if (_selectedAnswer == null || _quizFinished) return;
    setState(() {
      if (_currentQuestionIndex < _questions.length - 1) {
        _currentQuestionIndex++;
        _selectedAnswer = null;
      } else {
        _quizFinished = true;
      }
    });
  }

  Map<String, dynamic> get _scorePayload => {
    'score': _score,
    'total': _questions.length,
    'category': 'Science & Nature',
  };

  Future<void> _simulateSubmission() async {
    if (!_quizFinished || _submitting || _simulatedSubmissionComplete) return;
    setState(() => _submitting = true);
    try {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _simulatedSubmissionComplete = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Science Signal')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildError()
              : _quizFinished
              ? _buildResults()
              : _buildQuestion(),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _loadQuestions, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildQuestion() {
    final question = _questions[_currentQuestionIndex];
    final answered = _selectedAnswer != null;
    final correct = _selectedAnswer == question.correctAnswer;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Question ${_currentQuestionIndex + 1} of ${_questions.length}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (_currentQuestionIndex + 1) / _questions.length,
          ),
          const SizedBox(height: 12),
          Text('Score: $_score', textAlign: TextAlign.center),
          const SizedBox(height: 28),
          Text(
            question.text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 28),
          for (final answer in const ['True', 'False']) ...[
            FilledButton(
              onPressed: answered ? null : () => _selectAnswer(answer),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                disabledBackgroundColor: answered
                    ? answer == question.correctAnswer
                          ? Colors.green.shade700
                          : answer == _selectedAnswer
                          ? Colors.red.shade700
                          : Colors.grey.shade300
                    : null,
                disabledForegroundColor:
                    answered &&
                        (answer == question.correctAnswer ||
                            answer == _selectedAnswer)
                    ? Colors.white
                    : null,
              ),
              child: Text(answer),
            ),
            const SizedBox(height: 12),
          ],
          if (answered) ...[
            const SizedBox(height: 12),
            Text(
              correct
                  ? 'Correct! Great job!'
                  : 'Incorrect. The correct answer is ${question.correctAnswer}.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: correct ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: answered ? _nextQuestion : null,
            icon: const Icon(Icons.arrow_forward),
            label: Text(
              _currentQuestionIndex == _questions.length - 1
                  ? 'View Results'
                  : 'Next Question',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final payloadText = const JsonEncoder.withIndent('  ')
        .convert(_scorePayload);
    return ListView(
      children: [
        const Icon(Icons.emoji_events, size: 64, color: Colors.teal),
        const SizedBox(height: 12),
        Text(
          'Quiz Complete!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Your Score: $_score / ${_questions.length}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        Text('Answer Review', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (var i = 0; i < _questions.length; i++) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Question ${i + 1}: ${_questions[i].text}'),
                  const SizedBox(height: 8),
                  Text('Your answer: ${_userAnswers[i]}'),
                  Text('Correct answer: ${_questions[i].correctAnswer}'),
                  Text(
                    _userAnswers[i] == _questions[i].correctAnswer
                        ? 'Correct'
                        : 'Incorrect',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _userAnswers[i] == _questions[i].correctAnswer
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 16),
        Text(
          'Simulated score submission (no server request)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SelectableText(payloadText),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submitting || _simulatedSubmissionComplete
              ? null
              : _simulateSubmission,
          child: Text(
            _submitting
                ? 'Simulating submission...'
                : _simulatedSubmissionComplete
                ? 'Simulation Complete'
                : 'Simulate Score Submission',
          ),
        ),
        if (_simulatedSubmissionComplete) ...[
          const SizedBox(height: 8),
          const Text(
            'Simulation complete. No score was sent to or saved by a server.',
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _loadQuestions,
          icon: const Icon(Icons.refresh),
          label: const Text('Play Again (New Questions)'),
        ),
      ],
    );
  }
}
