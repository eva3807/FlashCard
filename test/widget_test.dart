import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flashcard/main.dart';
import 'package:flashcard/models.dart';
import 'package:flashcard/study_screen.dart';

void main() {
  setUp(() {
    // shared_preferences をテスト用のインメモリ実装に差し替える。
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('起動するとサンプルカードが一覧に出る', (WidgetTester tester) async {
    await tester.pumpWidget(const FlashCardApp());
    await tester.pumpAndSettle();

    expect(find.text('暗記カード'), findsOneWidget);
    expect(find.textContaining('学習を始める'), findsOneWidget);
    expect(find.textContaining('ワルファリン'), findsOneWidget);
  });

  testWidgets('カードを追加すると保存され一覧に増える', (WidgetTester tester) async {
    await tester.pumpWidget(const FlashCardApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'テスト問題');
    await tester.enterText(find.byType(TextField).at(1), 'テスト答え');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('テスト問題'), findsOneWidget);
    expect(find.textContaining('学習を始める（4枚）'), findsOneWidget);
  });

  testWidgets('学習モード: 答えは伏せられ、タップで開き、採点で次に進む',
      (WidgetTester tester) async {
    final store = CardStore();
    await store.load();
    final first = store.studyOrder().first;

    await tester.pumpWidget(MaterialApp(home: StudyScreen(store: store)));
    await tester.pumpAndSettle();

    // 最初は表だけ。裏は出ていない。
    expect(find.text(first.front), findsOneWidget);
    expect(find.text('タップで答えを表示'), findsOneWidget);
    expect(find.text(first.back), findsNothing);

    // 伏せている間は採点ボタンを押せない（見る前に押せてしまわないように）。
    final correctBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'わかった'),
    );
    expect(correctBtn.onPressed, isNull);

    // タップで裏返す。
    await tester.tap(find.text('タップで答えを表示'));
    await tester.pumpAndSettle();
    expect(find.text(first.back), findsOneWidget);

    // 採点すると次の問題に進み、また伏せた状態に戻る。
    await tester.tap(find.text('わかった'));
    await tester.pumpAndSettle();
    expect(find.text('学習  2 / 3'), findsOneWidget);
    expect(find.text('タップで答えを表示'), findsOneWidget);

    // 成績が保存されている。
    expect(store.cards.firstWhere((c) => c.id == first.id).correct, 1);
  });

  test('studyOrder は未回答を先頭に、次に正答率の低い順に並べる', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CardStore();
    await store.load();

    // seed3(未回答) はそのまま、seed1 を全問正解、seed2 を全問不正解にする。
    await store.grade('seed1', isCorrect: true);
    await store.grade('seed2', isCorrect: false);

    final order = store.studyOrder().map((c) => c.id).toList();
    expect(order.first, 'seed3'); // 未回答が最優先
    expect(order.indexOf('seed2'), lessThan(order.indexOf('seed1')));
  });
}
