import 'package:flutter/material.dart';
import 'import_screen.dart';
import 'models.dart';
import 'study_screen.dart';

void main() {
  runApp(const FlashCardApp());
}

class FlashCardApp extends StatefulWidget {
  const FlashCardApp({super.key});

  @override
  State<FlashCardApp> createState() => _FlashCardAppState();
}

class _FlashCardAppState extends State<FlashCardApp> {
  final _store = CardStore();

  @override
  void initState() {
    super.initState();
    _store.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '暗記カード',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3D5AFE),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3D5AFE),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: DeckScreen(store: _store),
    );
  }
}

class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key, required this.store});

  final CardStore store;

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  /// null は「すべて」。
  String? _deck;

  Future<void> _edit(BuildContext context, {Flashcard? card}) async {
    final frontCtrl = TextEditingController(text: card?.front ?? '');
    final backCtrl = TextEditingController(text: card?.back ?? '');
    final deckCtrl =
        TextEditingController(text: card?.deck ?? _deck ?? '未分類');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(card == null ? 'カードを追加' : 'カードを編集'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: frontCtrl,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: '表（問題）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: backCtrl,
                maxLines: 6,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: '裏（答え）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: deckCtrl,
                decoration: const InputDecoration(
                  labelText: 'デッキ（科目名など）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final front = frontCtrl.text.trim();
    final back = backCtrl.text.trim();
    final deck = deckCtrl.text.trim();
    if (front.isEmpty) return;

    if (card == null) {
      await widget.store.add(front, back, deck: deck.isEmpty ? '未分類' : deck);
    } else {
      await widget.store.update(card.id, front, back, deck: deck);
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final scope = _deck ?? 'すべてのデッキ';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('学習の進捗をリセット'),
        content: Text(
          '$scope の復習間隔と成績を初期化します。\n'
          'カードそのものは消えません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('リセット'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.store.resetProgress(deck: _deck);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final now = DateTime.now();
        final decks = store.decks;

        // 選んでいたデッキが空になったら「すべて」に戻す。
        if (_deck != null && !decks.contains(_deck)) _deck = null;

        final cards = _deck == null
            ? store.cards
            : store.cards.where((c) => c.deck == _deck).toList();
        final due = store.dueCount(now, deck: _deck);

        return Scaffold(
          appBar: AppBar(
            title: const Text('暗記カード'),
            actions: [
              IconButton(
                tooltip: '取り込み',
                icon: const Icon(Icons.upload_file),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ImportScreen(store: store, initialDeck: _deck),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'reset') _confirmReset(context);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'reset', child: Text('学習の進捗をリセット')),
                ],
              ),
            ],
          ),
          body: !store.loaded
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  // 既定の center だと子が内容幅に縮められ、デッキ列が
                  // 中央寄せになったうえチップのラベルが欠ける。
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 高さを固定した横 ListView にチップを入れるのも不可
                    //（高さを縛るとラベルが押し潰される）。高さは内容に決めさせる。
                    if (decks.length > 1)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Row(
                          children: [
                            _DeckChip(
                              label: 'すべて',
                              count: store.cards.length,
                              selected: _deck == null,
                              onTap: () => setState(() => _deck = null),
                            ),
                            for (final d in decks)
                              _DeckChip(
                                label: d,
                                count:
                                    store.cards.where((c) => c.deck == d).length,
                                selected: _deck == d,
                                onTap: () => setState(() => _deck = d),
                              ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: FilledButton.icon(
                        onPressed: due == 0
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        StudyScreen(store: store, deck: _deck),
                                  ),
                                ),
                        icon: const Icon(Icons.school),
                        label: Text(
                          due == 0 ? '今日ぶんは終わっています' : '復習する（$due枚）',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ),
                    Expanded(
                      child: cards.isEmpty
                          ? const Center(
                              child: Text('右上の取り込み、または + でカードを追加'))
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 88),
                              itemCount: cards.length,
                              itemBuilder: (context, i) {
                                final c = cards[i];
                                return Dismissible(
                                  key: ValueKey(c.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 24),
                                    color: Theme.of(context).colorScheme.error,
                                    child: Icon(
                                      Icons.delete,
                                      color:
                                          Theme.of(context).colorScheme.onError,
                                    ),
                                  ),
                                  onDismissed: (_) => store.remove(c.id),
                                  child: ListTile(
                                    title: Text(
                                      c.front,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      c.back.replaceAll('\n', ' '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: _DueChip(card: c, now: now),
                                    onTap: () => _edit(context, card: c),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _edit(context),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}

class _DeckChip extends StatelessWidget {
  const _DeckChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  // ChoiceChip は使わない。Flutter web で日本語ラベルの幅を大きく過小に見積もり、
  // 「すべて」が「す」まで切り詰められた。同じ文字列が AppBar・ListTile・
  // FilledButton では正しく出るので Chip 固有の挙動。iOS で再現するかは未確認だが、
  // 描画実績のあるボタンで組めば確実なので、そちらを使う。
  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
    final child = Text('$label  $count');

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: selected
          ? FilledButton.tonal(onPressed: onTap, style: style, child: child)
          : OutlinedButton(onPressed: onTap, style: style, child: child),
    );
  }
}

/// 一覧の右端。次にいつ復習するかを出す。
/// 学習状態は「正答率」より「次の期日」の方が行動に直結する。
class _DueChip extends StatelessWidget {
  const _DueChip({required this.card, required this.now});

  final Flashcard card;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (card.isNew) {
      return Text('新規',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.primary));
    }
    if (card.isDue(now)) {
      return Text('今日',
          style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.error, fontWeight: FontWeight.bold));
    }
    final days = DateTime(card.due.year, card.due.month, card.due.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final label = days < 30
        ? '$days日後'
        : days < 365
            ? '${(days / 30).toStringAsFixed(0)}か月後'
            : '${(days / 365).toStringAsFixed(1)}年後';
    return Text(label,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: theme.colorScheme.outline));
  }
}
