import 'package:flutter/material.dart';
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

class DeckScreen extends StatelessWidget {
  const DeckScreen({super.key, required this.store});

  final CardStore store;

  Future<void> _edit(BuildContext context, {Flashcard? card}) async {
    final frontCtrl = TextEditingController(text: card?.front ?? '');
    final backCtrl = TextEditingController(text: card?.back ?? '');

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
    if (front.isEmpty) return;

    if (card == null) {
      await store.add(front, back);
    } else {
      await store.update(card.id, front, back);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final cards = store.cards;
        return Scaffold(
          appBar: AppBar(
            title: const Text('暗記カード'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'reset') store.resetStats();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'reset', child: Text('成績をリセット')),
                ],
              ),
            ],
          ),
          body: !store.loaded
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: FilledButton.icon(
                        onPressed: cards.isEmpty
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => StudyScreen(store: store),
                                  ),
                                ),
                        icon: const Icon(Icons.school),
                        label: Text('学習を始める（${cards.length}枚）'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ),
                    Expanded(
                      child: cards.isEmpty
                          ? const Center(child: Text('右下の + でカードを追加'))
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
                                    trailing: _AccuracyChip(card: c),
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

class _AccuracyChip extends StatelessWidget {
  const _AccuracyChip({required this.card});

  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    if (card.accuracy < 0) {
      return Text(
        '未',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      );
    }
    final pct = (card.accuracy * 100).round();
    final color = pct >= 80
        ? Colors.green
        : pct >= 50
            ? Colors.orange
            : Theme.of(context).colorScheme.error;
    return Text(
      '$pct%',
      style: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }
}
