import 'package:flutter/material.dart';
import 'models.dart';

/// 貼り付けたテキストからカードを一括登録する画面。
///
/// 手打ちだけでは数百枚を回せないので、Excel やスプレッドシートの
/// 2列をコピーしてそのまま貼れるようにしてある（区切りはタブ）。
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.store, this.initialDeck});

  final CardStore store;
  final String? initialDeck;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _textCtrl = TextEditingController();
  late final TextEditingController _deckCtrl;
  List<ParsedRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _deckCtrl = TextEditingController(text: widget.initialDeck ?? '');
    _textCtrl.addListener(() {
      setState(() => _rows = CardStore.parseRows(_textCtrl.text));
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _deckCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final (added, skipped) =
        await widget.store.importRows(_rows, _deckCtrl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skipped == 0 ? '$added 枚を追加しました' : '$added 枚を追加、$skipped 枚は重複のため除外',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final withBack = _rows.where((r) => r.back.isNotEmpty).length;

    return Scaffold(
      appBar: AppBar(title: const Text('カードの取り込み')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Excel やスプレッドシートで「表」「裏」の2列を選んでコピーし、'
            '下の欄に貼り付けてください。1行が1枚になります。',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '区切りはタブ。タブが無い行は表だけのカードになります。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _deckCtrl,
            decoration: const InputDecoration(
              labelText: '取り込み先のデッキ（科目名など）',
              hintText: '空欄なら「未分類」',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textCtrl,
            maxLines: 12,
            minLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: '貼り付け',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_rows.isNotEmpty) ...[
            Text(
              '${_rows.length} 枚を認識（うち裏が入っているもの $withBack 枚）',
              style: theme.textTheme.titleSmall,
            ),
            if (withBack < _rows.length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '裏が空のカードは、タブ区切りになっていない可能性があります。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final r in _rows.take(5))
                    ListTile(
                      dense: true,
                      title: Text(r.front,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        r.back.isEmpty ? '（裏が空）' : r.back.replaceAll('\n', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_rows.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('… 他 ${_rows.length - 5} 枚',
                          style: theme.textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _rows.isEmpty ? null : _run,
            icon: const Icon(Icons.download),
            label: Text(_rows.isEmpty ? '取り込む' : '${_rows.length} 枚を取り込む'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '同じデッキに同じ表のカードが既にあれば、そのぶんは飛ばします。'
            '同じ範囲を二度貼っても重複しません。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
