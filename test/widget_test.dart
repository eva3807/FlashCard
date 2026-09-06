import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flashcard/import_screen.dart';
import 'package:flashcard/main.dart';
import 'package:flashcard/models.dart';
import 'package:flashcard/study_screen.dart';

Future<CardStore> _freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = CardStore();
  await store.load();
  return store;
}

void main() {
  setUp(() {
    // shared_preferences をテスト用のインメモリ実装に差し替える。
    SharedPreferences.setMockInitialValues({});
  });

  group('SM-2', () {
    test('できた を繰り返すと間隔が 1日 → 6日 → ease倍 と伸びる', () {
      final now = DateTime(2026, 9, 6);
      final c = Flashcard(id: 'x', front: 'a', back: 'b');

      c.applyRating(Rating.good, now);
      expect(c.intervalDays, 1);
      expect(c.due, DateTime(2026, 9, 7));

      c.applyRating(Rating.good, now);
      expect(c.intervalDays, 6);

      c.applyRating(Rating.good, now);
      expect(c.intervalDays, (6 * 2.5).round()); // 15
    });

    test('もう一度 は間隔を潰し ease を下げ、期日を今日に戻す', () {
      final now = DateTime(2026, 9, 6);
      final c = Flashcard(id: 'x', front: 'a', back: 'b');
      c.applyRating(Rating.good, now);
      c.applyRating(Rating.good, now);
      expect(c.intervalDays, 6);

      c.applyRating(Rating.again, now);
      expect(c.reps, 0);
      expect(c.intervalDays, 0);
      expect(c.ease, closeTo(2.30, 1e-9));
      expect(c.isDue(now), isTrue);
    });

    test('ease は 1.3 を下回らない', () {
      final now = DateTime(2026, 9, 6);
      final c = Flashcard(id: 'x', front: 'a', back: 'b');
      for (var i = 0; i < 20; i++) {
        c.applyRating(Rating.again, now);
      }
      expect(c.ease, 1.3);
    });

    test('簡単 は できた より先の期日になる', () {
      final now = DateTime(2026, 9, 6);
      final good = Flashcard(id: 'g', front: 'a', back: 'b')
        ..applyRating(Rating.good, now);
      final easy = Flashcard(id: 'e', front: 'a', back: 'b')
        ..applyRating(Rating.easy, now);
      expect(easy.intervalDays, greaterThan(good.intervalDays));
      expect(easy.ease, greaterThan(good.ease));
    });
  });

  group('出題キュー', () {
    test('期限が来ていないカードは出題されない', () async {
      final store = await _freshStore();
      final now = DateTime(2026, 9, 6);

      // 全カードを「できた」にすると、最短でも翌日送りになる。
      for (final c in store.cards.toList()) {
        await store.rate(c.id, Rating.good, now: now);
      }
      expect(store.studyQueue(now), isEmpty);
      expect(store.dueCount(now), 0);

      // 翌日には戻ってくる。
      expect(store.studyQueue(now.add(const Duration(days: 1))), isNotEmpty);
    });

    test('デッキで絞り込める', () async {
      final store = await _freshStore();
      final now = DateTime(2026, 9, 6);
      expect(store.decks, contains('薬理'));
      final q = store.studyQueue(now, deck: '薬理');
      expect(q, isNotEmpty);
      expect(q.every((c) => c.deck == '薬理'), isTrue);
    });

    test('順序は実行ごとに変わらない', () async {
      final store = await _freshStore();
      final now = DateTime(2026, 9, 6);
      final a = store.studyQueue(now).map((c) => c.id).toList();
      final b = store.studyQueue(now).map((c) => c.id).toList();
      expect(a, b);
    });
  });

  group('取り込み', () {
    test('タブ区切りを表と裏に分解する', () {
      final rows = CardStore.parseRows(
        'アスピリン\tCOX-1を不可逆的にアセチル化\n'
        '\n' // 空行は無視
        'タブ無しの行\n'
        '3列\t裏1\t裏2\n',
      );
      expect(rows.length, 3);
      expect(rows[0].front, 'アスピリン');
      expect(rows[0].back, 'COX-1を不可逆的にアセチル化');
      expect(rows[1].back, ''); // タブが無い行は裏が空
      expect(rows[2].back, '裏1\n裏2'); // 3列目以降は改行で連結
    });

    test('同じデッキの同じ表は重複登録しない', () async {
      final store = await _freshStore();
      final rows = CardStore.parseRows('A\t1\nB\t2\n');

      var (added, skipped) = await store.importRows(rows, '生化学');
      expect(added, 2);
      expect(skipped, 0);

      (added, skipped) = await store.importRows(rows, '生化学');
      expect(added, 0);
      expect(skipped, 2);

      // デッキが違えば別のカードとして入る。
      (added, skipped) = await store.importRows(rows, '薬理');
      expect(added, 2);
    });

    test('デッキ名が空なら未分類に入る', () async {
      final store = await _freshStore();
      await store.importRows(CardStore.parseRows('X\tY'), '   ');
      expect(store.cards.any((c) => c.front == 'X' && c.deck == '未分類'),
          isTrue);
    });
  });

  group('永続化', () {
    test('保存した SRS の状態が読み直せる', () async {
      final store = await _freshStore();
      final now = DateTime(2026, 9, 6);
      final id = store.cards.first.id;
      await store.rate(id, Rating.good, now: now);
      await store.rate(id, Rating.good, now: now);

      final reloaded = CardStore();
      await reloaded.load();
      final c = reloaded.cards.firstWhere((c) => c.id == id);
      expect(c.reps, 2);
      expect(c.intervalDays, 6);
      expect(c.deck, isNotEmpty);
    });

    test('deck と SRS を持たない旧形式の JSON も読める', () {
      final c = Flashcard.fromJson({
        'id': 'old',
        'front': '表',
        'back': '裏',
        'correct': 3,
        'wrong': 1,
      });
      expect(c.deck, '未分類');
      expect(c.reps, 0);
      expect(c.ease, 2.5);
      expect(c.isNew, isTrue);
      expect(c.isDue(DateTime.now()), isTrue); // 未学習なので即出題対象
    });
  });

  group('画面', () {
    testWidgets('起動するとデッキと復習件数が出る', (tester) async {
      await tester.pumpWidget(const FlashCardApp());
      await tester.pumpAndSettle();

      expect(find.text('暗記カード'), findsOneWidget);
      expect(find.textContaining('復習する'), findsOneWidget);
      expect(find.textContaining('ワルファリン'), findsOneWidget);
    });

    testWidgets('学習: 答えは伏せられ、タップで開き、評価で次に進む', (tester) async {
      final store = await _freshStore();
      final first = store.studyQueue(DateTime.now()).first;

      await tester.pumpWidget(MaterialApp(home: StudyScreen(store: store)));
      await tester.pumpAndSettle();

      expect(find.text(first.front), findsOneWidget);
      expect(find.text('タップで答えを表示'), findsOneWidget);
      expect(find.text(first.back), findsNothing);

      // 伏せている間は評価ボタンを押せない。
      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'できた'),
      );
      expect(btn.onPressed, isNull);

      await tester.tap(find.text('タップで答えを表示'));
      await tester.pumpAndSettle();
      expect(find.text(first.back), findsOneWidget);

      await tester.tap(find.text('できた'));
      await tester.pumpAndSettle();
      expect(find.text('タップで答えを表示'), findsOneWidget);
      expect(store.cards.firstWhere((c) => c.id == first.id).reps, 1);
    });

    testWidgets('学習: もう一度 を押したカードは同じセッションで再出題される',
        (tester) async {
      final store = await _freshStore();
      final total = store.studyQueue(DateTime.now()).length;

      await tester.pumpWidget(MaterialApp(home: StudyScreen(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('タップで答えを表示'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('もう一度'));
      await tester.pumpAndSettle();

      // キューが1枚増えている（末尾に積み直された）。
      expect(find.textContaining('/ ${total + 1}'), findsOneWidget);
    });

    testWidgets('取り込み画面は貼り付けた行数を先に見せる', (tester) async {
      final store = await _freshStore();
      await tester.pumpWidget(MaterialApp(home: ImportScreen(store: store)));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '貼り付け'),
        'A\t1\nB\t2\nC\t3',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('3 枚を認識'), findsOneWidget);

      // 取り込みボタンは ListView の下端にあり、初期表示では組み立てられていない。
      await tester.dragUntilVisible(
        find.textContaining('枚を取り込む'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.textContaining('3 枚を取り込む'), findsOneWidget);
    });
  });
}
