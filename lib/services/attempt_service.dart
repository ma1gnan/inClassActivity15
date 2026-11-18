import 'package:cloud_firestore/cloud_firestore.dart';

class AttemptService {
  AttemptService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _attemptRef(
    String uid,
    String roundId,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('attempts')
        .doc(roundId);
  }

  Future<void> saveAttempt({
    required String uid,
    required String roundId,
    required int correctCount,
  }) async {
    if (uid.isEmpty ||
        roundId.isEmpty ||
        correctCount < 0 ||
        correctCount > 5) {
      throw ArgumentError('Invalid quiz attempt.');
    }

    final ref = _attemptRef(uid, roundId);

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);

      if (existing.exists) {
        final data = existing.data();

        if (data == null ||
            data['schemaVersion'] != 1 ||
            data['variant'] != 'B' ||
            data['categoryId'] != 17 ||
            data['questionCount'] != 5 ||
            data['correctCount'] != correctCount) {
          throw StateError('Round ID collision: saved data differs.');
        }

        // Matching attempt already exists: reuse it.
        return;
      }

      transaction.set(ref, {
        'schemaVersion': 1,
        'variant': 'B',
        'categoryId': 17,
        'questionCount': 5,
        'correctCount': correctCount,
        'submittedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> verifyAttempt({
    required String uid,
    required String roundId,
    required int correctCount,
  }) async {
    final snapshot = await _attemptRef(
      uid,
      roundId,
    ).get(const GetOptions(source: Source.server));

    final data = snapshot.data();

    if (!snapshot.exists ||
        snapshot.metadata.isFromCache ||
        snapshot.metadata.hasPendingWrites ||
        data == null ||
        data.length != 6 ||
        data['schemaVersion'] != 1 ||
        data['variant'] != 'B' ||
        data['categoryId'] != 17 ||
        data['questionCount'] != 5 ||
        data['correctCount'] != correctCount ||
        data['submittedAt'] is! Timestamp) {
      throw StateError('Server verification failed.');
    }
  }
}
