import 'package:flutter/material.dart';
import 'models.dart';

/// 学習モード。カードをタップで裏返し、3段階で自己評価する。
///
/// キューは「期限が来たカード」だけ。again と評価したカードはその場で
/// 末尾に積み直すので、覚えていないものはセッション内で必ずもう一度出る。
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.store, this.deck});

  final CardStore store;

  /// null なら全デッキ。
  final String? deck;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  late List<Flashcard> _queue;
  int _index = 0;
  bool _revealed = false;
  int _done = 0;
  int _againCount = 0;

  @override
  void initState() {
    super.initState();
    _queue = widget.store.studyQueue(DateTime.now(), deck: widget.deck);
  }

  Future<void> _rate(Rating rating) async {
    final card = _queue[_index];
    await widget.store.rate(card.id, rating);
    if (!mounted) return;
    setState(() {
      if (rating == Rating.again) {
        // 覚えていないので、このセッションの最後にもう一度出す。
        _queue.add(card);
        _againCount++;
      } else {
        _done++;
      }
      _index++;
      _revealed = false;
    });
  }

  /// そのボタンを押したら次はいつ出るかの表示。
  /// 間隔が見えると「簡単」を押しすぎたときに自分で気づける。
  String _nextLabel(Rating r) {
    if (r == Rating.again) return '今日中';
    final c = _queue[_index];
    final probe = Flashcard(
      id: c.id,
      front: c.front,
      back: c.back,
      reps: c.reps,
      intervalDays: c.intervalDays,
      ease: c.ease,
    );
    probe.applyRating(r, DateTime.now());
    final d = probe.intervalDays;
    if (d < 30) return '$d日';
    if (d < 365) return '${(d / 30).toStringAsFixed(1)}か月';
    return '${(d / 365).toStringAsFixed(1)}年';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.deck == null ? '学習' : '学習 · ${widget.deck}';

    if (_queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('今日ぶんは終わっています', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '期限が来たカードはありません。\n次の復習日まで待つのがいちばん効率が良いです。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_index >= _queue.length) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('お疲れさま', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text('$_done 枚を完了', style: theme.textTheme.titleLarge),
              if (_againCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'うち $_againCount 回は「もう一度」',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              const SizedBox(height: 28),
              FilledButton(
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
      appBar: AppBar(title: Text('$title  ${_index + 1} / ${_queue.length}')),
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
                            card.back.isEmpty ? '（裏は未入力）' : card.back,
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _RateButton(
                      label: 'もう一度',
                      sub: _revealed ? _nextLabel(Rating.again) : '',
                      tone: theme.colorScheme.error,
                      onPressed: _revealed ? () => _rate(Rating.again) : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RateButton(
                      label: 'できた',
                      sub: _revealed ? _nextLabel(Rating.good) : '',
                      tone: theme.colorScheme.primary,
                      filled: true,
                      onPressed: _revealed ? () => _rate(Rating.good) : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RateButton(
                      label: '簡単',
                      sub: _revealed ? _nextLabel(Rating.easy) : '',
                      tone: theme.colorScheme.tertiary,
                      onPressed: _revealed ? () => _rate(Rating.easy) : null,
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

class _RateButton extends StatelessWidget {
  const _RateButton({
    required this.label,
    required this.sub,
    required this.tone,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final String sub;
  final Color tone;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (sub.isNotEmpty)
          Text(sub, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
    final style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size.fromHeight(56)),
      padding: WidgetStateProperty.all(EdgeInsets.zero),
    );
    return filled
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(
            onPressed: onPressed,
            style: style.copyWith(
              foregroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.disabled) ? null : tone,
              ),
            ),
            child: child,
          );
  }
}
