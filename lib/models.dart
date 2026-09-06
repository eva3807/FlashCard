import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 学習後の自己評価。SM-2 の quality を3段階に落としたもの。
///
/// Anki と同じ割り切り。6段階(0-5)は自己評価がぶれて精度が出ないため、
/// 「思い出せなかった / 思い出せた / 即答できた」の3つに絞る。
enum Rating { again, good, easy }

/// 日付だけを見た比較用（時刻を捨てる）。期限は「その日じゅう」の粒度で扱う。
DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

class Flashcard {
  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.deck = '未分類',
    this.correct = 0,
    this.wrong = 0,
    this.reps = 0,
    this.intervalDays = 0,
    this.ease = 2.5,
    DateTime? due,
  }) : due = due ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  String front;
  String back;
  String deck;

  /// 累計の正誤。一覧に定着度を出すためだけに使う（出題順には使わない）。
  int correct;
  int wrong;

  /// SM-2 の状態。
  int reps; // 連続で正解できた回数。again で 0 に戻る
  int intervalDays; // 次の復習までの日数
  double ease; // 易しさ係数。難しいカードほど下がり、間隔が伸びにくくなる
  DateTime due; // 次に出題する日

  bool get isNew => reps == 0 && intervalDays == 0;

  /// 期限が来ているか。未学習のカードは常に対象。
  bool isDue(DateTime now) => !_dayOf(due).isAfter(_dayOf(now));

  double get accuracy {
    final total = correct + wrong;
    return total == 0 ? -1 : correct / total;
  }

  /// SM-2 を適用して次回の出題日を決める。
  ///
  /// 原典との違いは2点:
  ///  - quality を3段階に丸めている
  ///  - again のとき間隔を0にして「同じセッション中に出し直す」ようにしている
  ///    （翌日送りにすると、覚えていないカードをその場で潰せないため）
  void applyRating(Rating rating, DateTime now) {
    if (rating == Rating.again) {
      correct += 0;
      wrong++;
      reps = 0;
      intervalDays = 0;
      ease = math.max(1.3, ease - 0.20);
      due = now; // 今日ぶんとして再度キューに乗る
      return;
    }

    correct++;
    final bonus = rating == Rating.easy ? 1.3 : 1.0;

    if (reps == 0) {
      intervalDays = rating == Rating.easy ? 4 : 1;
    } else if (reps == 1) {
      intervalDays = rating == Rating.easy ? 8 : 6;
    } else {
      intervalDays = (intervalDays * ease * bonus).round().clamp(1, 3650);
    }

    reps++;
    if (rating == Rating.easy) ease = math.min(3.0, ease + 0.15);
    due = _dayOf(now).add(Duration(days: intervalDays));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'front': front,
        'back': back,
        'deck': deck,
        'correct': correct,
        'wrong': wrong,
        'reps': reps,
        'intervalDays': intervalDays,
        'ease': ease,
        'due': due.toIso8601String(),
      };

  /// 旧バージョンが書いた JSON（deck / SRS の各項目が無い）も読めるようにしてある。
  /// 欠けている場合は「未学習の未分類カード」として扱う。
  factory Flashcard.fromJson(Map<String, dynamic> j) => Flashcard(
        id: j['id'] as String,
        front: j['front'] as String? ?? '',
        back: j['back'] as String? ?? '',
        deck: (j['deck'] as String?)?.trim().isNotEmpty == true
            ? (j['deck'] as String).trim()
            : '未分類',
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        wrong: (j['wrong'] as num?)?.toInt() ?? 0,
        reps: (j['reps'] as num?)?.toInt() ?? 0,
        intervalDays: (j['intervalDays'] as num?)?.toInt() ?? 0,
        ease: (j['ease'] as num?)?.toDouble() ?? 2.5,
        due: DateTime.tryParse(j['due'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// 貼り付けたテキストを解釈した結果の1行分。
class ParsedRow {
  ParsedRow(this.front, this.back);
  final String front;
  final String back;
}

/// カード一覧の保持と端末内への永続化。
class CardStore extends ChangeNotifier {
  static const _key = 'flashcards_v1';

  final List<Flashcard> _cards = [];
  bool _loaded = false;

  List<Flashcard> get cards => List.unmodifiable(_cards);
  bool get loaded => _loaded;

  /// 存在するデッキ名。カード数の多い順、同数なら名前順。
  List<String> get decks {
    final counts = <String, int>{};
    for (final c in _cards) {
      counts[c.deck] = (counts[c.deck] ?? 0) + 1;
    }
    final names = counts.keys.toList();
    names.sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
    return names;
  }

  int dueCount(DateTime now, {String? deck}) => _cards
      .where((c) => (deck == null || c.deck == deck) && c.isDue(now))
      .length;

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

  int _seq = 0;
  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  Future<void> add(String front, String back, {String deck = '未分類'}) async {
    _cards.add(Flashcard(id: _newId(), front: front, back: back, deck: deck));
    await _persist();
    notifyListeners();
  }

  Future<void> update(String id, String front, String back,
      {String? deck}) async {
    final c = _cards.firstWhere((c) => c.id == id);
    c.front = front;
    c.back = back;
    if (deck != null && deck.trim().isNotEmpty) c.deck = deck.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _cards.removeWhere((c) => c.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> rate(String id, Rating rating, {DateTime? now}) async {
    final c = _cards.firstWhere((c) => c.id == id);
    c.applyRating(rating, now ?? DateTime.now());
    await _persist();
    notifyListeners();
  }

  /// 学習の進捗（間隔・期日）だけを消す。カード本体は残す。
  Future<void> resetProgress({String? deck}) async {
    for (final c in _cards) {
      if (deck != null && c.deck != deck) continue;
      c.correct = 0;
      c.wrong = 0;
      c.reps = 0;
      c.intervalDays = 0;
      c.ease = 2.5;
      c.due = DateTime.fromMillisecondsSinceEpoch(0);
    }
    await _persist();
    notifyListeners();
  }

  /// 出題キュー。期限が来たカードだけを、期日の古い順に返す。
  /// 期日が同じなら未学習を先に出す（新規は早めに1回目を通したいため）。
  List<Flashcard> studyQueue(DateTime now, {String? deck}) {
    final list = _cards
        .where((c) => (deck == null || c.deck == deck) && c.isDue(now))
        .toList();
    list.sort((a, b) {
      final byDue = a.due.compareTo(b.due);
      if (byDue != 0) return byDue;
      if (a.isNew != b.isNew) return a.isNew ? -1 : 1;
      return a.id.compareTo(b.id); // 実行ごとに順が変わらないようにする
    });
    return list;
  }

  /// `表<TAB>裏` 形式のテキストを解釈する。Excel / スプレッドシートから
  /// 2列を選んでコピーするとこの形式になるので、それをそのまま貼れる。
  ///
  /// - タブが無い行は表だけのカードとして扱う（裏は空）
  /// - 3列以上ある場合、2列目以降を改行で連結して裏にする
  /// - 空行は無視する
  static List<ParsedRow> parseRows(String text) {
    final rows = <ParsedRow>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\t');
      final front = parts.first.trim();
      if (front.isEmpty) continue;
      final back = parts.length > 1
          ? parts.sublist(1).map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n')
          : '';
      rows.add(ParsedRow(front, back));
    }
    return rows;
  }

  /// 一括登録。同じデッキ内に同じ表のカードが既にあれば飛ばす。
  /// 戻り値は (追加した件数, 重複で飛ばした件数)。
  Future<(int, int)> importRows(List<ParsedRow> rows, String deck) async {
    final d = deck.trim().isEmpty ? '未分類' : deck.trim();
    final existing = _cards
        .where((c) => c.deck == d)
        .map((c) => c.front)
        .toSet();

    var added = 0;
    var skipped = 0;
    for (final r in rows) {
      if (existing.contains(r.front)) {
        skipped++;
        continue;
      }
      _cards.add(
        Flashcard(id: _newId(), front: r.front, back: r.back, deck: d),
      );
      existing.add(r.front);
      added++;
    }
    if (added > 0) await _persist();
    notifyListeners();
    return (added, skipped);
  }

  List<Flashcard> _seed() => [
        Flashcard(
          id: 'seed1',
          deck: '薬理',
          front: 'ワルファリンの作用機序',
          back: 'ビタミンK エポキシド還元酵素(VKORC1)を阻害し、\n'
              'II・VII・IX・X 因子の γ-カルボキシル化を妨げる。',
        ),
        Flashcard(
          id: 'seed2',
          deck: '薬理',
          front: 'CYP2C19 で代謝され、活性代謝物が効く抗血小板薬',
          back: 'クロピドグレル。PM(poor metabolizer)では効果減弱。\n'
              'プラスグレルは CYP2C19 の影響を受けにくい。',
        ),
        Flashcard(
          id: 'seed3',
          deck: '使い方',
          front: 'カードをまとめて入れるには',
          back: '右上の「取り込み」から、Excel の2列をコピーして貼り付ける。\n'
              '「表<TAB>裏」の形式なら何行でも一度に登録できる。',
        ),
      ];
}
