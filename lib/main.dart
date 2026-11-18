import 'dart:async';
import 'dart:convert';

import 'screens/auth_gate.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'services/attempt_service.dart';
import 'firebase_options.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ScienceSignalApp());
}

class ScienceSignalApp extends StatelessWidget {
  const ScienceSignalApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Science Signal',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: AuthGate(
      signedInBuilder: (User user) {
        return ScienceQuizScreen(key: ValueKey(user.uid));
      },
    ),
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

  int _requestVersion = 0;
  String? _roundId;
  String? _roundUid;
  bool _verifying = false;
  bool _cloudVerified = false;
  String? _cloudMessage;

  String _createRoundId() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .collection('attempts')
        .doc()
        .id;
  }

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

  Future<void> _submitScore() async {
    if (!_quizFinished ||
        _submitting ||
        _verifying ||
        _cloudVerified ||
        _roundId != null ||
        _roundUid != null) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _cloudMessage = 'Please sign in again.');
      return;
    }

    final uid = user.uid;
    final roundId = _createRoundId();
    final correctCount = _score;
    final service = AttemptService();

    setState(() {
      _roundId = roundId;
      _roundUid = uid;
      _submitting = true;
      _cloudMessage = 'Saving quiz score to Firestore...';
    });

    try {
      await service.saveAttempt(
        uid: uid,
        roundId: roundId,
        correctCount: correctCount,
      );

      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }

      setState(() {
        _submitting = false;
        _verifying = true;
        _cloudMessage = 'Write acknowledged. Verifying with server...';
      });

      await service.verifyAttempt(
        uid: uid,
        roundId: roundId,
        correctCount: correctCount,
      );

      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }

      setState(() {
        _verifying = false;
        _cloudVerified = true;
        _cloudMessage = 'Cloud verified: quiz score saved successfully.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _submitting = false;
        _verifying = false;
        _cloudMessage = 'Submission or verification needs attention: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Science Signal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed:
                _submitting ||
                    _verifying ||
                    (_roundId != null && !_cloudVerified)
                ? null
                : () async {
                    await FirebaseAuth.instance.signOut();
                  },
          ),
        ],
      ),
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
          'Cloud Firestore Score Submission',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SelectableText(payloadText),
        const SizedBox(height: 12),
        FilledButton(
          onPressed:
              _submitting || _verifying || _cloudVerified || _roundId != null
              ? null
              : _submitScore,
          child: Text(
            _submitting
                ? 'Saving...'
                : _verifying
                ? 'Verifying...'
                : _cloudVerified
                ? 'Cloud Verified'
                : 'Submit Score to Cloud',
          ),
        ),
        if (_cloudMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_cloudMessage!),
          ),
      ],
    );
  }
}
