import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1枚のカード。表(front)・裏(back)と、正誤の累計を持つ。
class Flashcard {
  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.correct = 0,
    this.wrong = 0,
  });

  final String id;
  String front;
  String back;
  int correct;
  int wrong;

  /// 正答率。未回答は -1（並べ替えで「未着手」を先頭に出すため）。
  double get accuracy {
    final total = correct + wrong;
    return total == 0 ? -1 : correct / total;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'front': front,
        'back': back,
        'correct': correct,
        'wrong': wrong,
      };

  factory Flashcard.fromJson(Map<String, dynamic> j) => Flashcard(
        id: j['id'] as String,
        front: j['front'] as String? ?? '',
        back: j['back'] as String? ?? '',
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        wrong: (j['wrong'] as num?)?.toInt() ?? 0,
      );
}

/// カード一覧の保持と端末内への永続化。
///
/// 保存先は shared_preferences（iOS では NSUserDefaults）。
/// このプラグインが CocoaPods 経由で入るので、CI のビルドが通れば
/// 「プラグイン入りの実アプリがビルドできる」ことの証明になる。
class CardStore extends ChangeNotifier {
  static const _key = 'flashcards_v1';

  final List<Flashcard> _cards = [];
  bool _loaded = false;

  List<Flashcard> get cards => List.unmodifiable(_cards);
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _cards.clear();
    if (raw == null) {
      _cards.addAll(_seed());
      await _persist();
    } else {
      final list = jsonDecode(raw) as List<dynamic>;
      _cards.addAll(
        list.map((e) => Flashcard.fromJson(e as Map<String, dynamic>)),
      );
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_cards.map((c) => c.toJson()).toList()),
    );
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_cards.length}';

  Future<void> add(String front, String back) async {
    _cards.add(Flashcard(id: _newId(), front: front, back: back));
    await _persist();
    notifyListeners();
  }

  Future<void> update(String id, String front, String back) async {
    final c = _cards.firstWhere((c) => c.id == id);
    c.front = front;
    c.back = back;
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _cards.removeWhere((c) => c.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> grade(String id, {required bool isCorrect}) async {
    final c = _cards.firstWhere((c) => c.id == id);
    if (isCorrect) {
      c.correct++;
    } else {
      c.wrong++;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> resetStats() async {
    for (final c in _cards) {
      c.correct = 0;
      c.wrong = 0;
    }
    await _persist();
    notifyListeners();
  }

  /// 出題順: 未着手 → 正答率が低い順。苦手なカードが先に回ってくる。
  ///
  /// Dart の List.sort は安定ソートを保証しない。正答率が同じカード
  /// （特に全部未回答の初回）の順が実行ごとに変わらないよう、
  /// 一覧での並び順を第2キーにして明示的に決定的にしている。
  List<Flashcard> studyOrder() {
    final index = {for (var i = 0; i < _cards.length; i++) _cards[i].id: i};
    final list = [..._cards];
    list.sort((a, b) {
      final byAccuracy = a.accuracy.compareTo(b.accuracy);
      if (byAccuracy != 0) return byAccuracy;
      return index[a.id]!.compareTo(index[b.id]!);
    });
    return list;
  }

  List<Flashcard> _seed() => [
        Flashcard(
          id: 'seed1',
          front: 'ワルファリンの作用機序',
          back: 'ビタミンK エポキシド還元酵素(VKORC1)を阻害し、\n'
              'II・VII・IX・X 因子の γ-カルボキシル化を妨げる。',
        ),
        Flashcard(
          id: 'seed2',
          front: 'CYP2C19 で代謝され、活性代謝物が効く抗血小板薬',
          back: 'クロピドグレル。PM(poor metabolizer)では効果減弱。\n'
              'プラスグレルは CYP2C19 の影響を受けにくい。',
        ),
        Flashcard(
          id: 'seed3',
          front: 'このアプリの使い方',
          back: '右下の + でカードを追加。上の「学習」で出題が始まる。\n'
              'このサンプルカードは削除して構わない。',
        ),
      ];
}
