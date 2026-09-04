import 'package:flutter/material.dart';
import 'models.dart';

/// 学習モード。カードをタップで裏返し、わかった/わからないで仕分ける。
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.store});

  final CardStore store;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  late List<Flashcard> _queue;
  int _index = 0;
  bool _revealed = false;
  int _correctThisRound = 0;

  @override
  void initState() {
    super.initState();
    _queue = widget.store.studyOrder();
  }

  Future<void> _answer(bool isCorrect) async {
    await widget.store.grade(_queue[_index].id, isCorrect: isCorrect);
    if (!mounted) return;
    setState(() {
      if (isCorrect) _correctThisRound++;
      _index++;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('学習')),
        body: const Center(child: Text('カードがありません')),
      );
    }

    if (_index >= _queue.length) {
      return Scaffold(
        appBar: AppBar(title: const Text('学習')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('お疲れさま', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                '$_correctThisRound / ${_queue.length} 正解',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => setState(() {
                  _queue = widget.store.studyOrder();
                  _index = 0;
                  _revealed = false;
                  _correctThisRound = 0;
                }),
                child: const Text('もう一周'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('一覧に戻る'),
              ),
            ],
          ),
        ),
      );
    }

    final card = _queue[_index];

    return Scaffold(
      appBar: AppBar(title: Text('学習  ${_index + 1} / ${_queue.length}')),
      body: Column(
        children: [
          LinearProgressIndicator(value: _index / _queue.length),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _revealed = !_revealed),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _revealed
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          card.front,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                        if (_revealed) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Divider(),
                          ),
                          Text(
                            card.back,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(top: 28),
                            child: Text(
                              'タップで答えを表示',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _revealed ? () => _answer(false) : null,
                      icon: const Icon(Icons.close),
                      label: const Text('まだ'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _revealed ? () => _answer(true) : null,
                      icon: const Icon(Icons.check),
                      label: const Text('わかった'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
