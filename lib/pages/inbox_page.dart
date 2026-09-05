import 'dart:async';
import 'package:flutter/material.dart';
import '../mail_api.dart';

/// Tab2: 收件箱（5s 自动刷新 + 卡片列表）
class InboxPage extends StatefulWidget {
  final String? addr;
  final String? token;
  final VoidCallback? goGenerate;
  const InboxPage({
    super.key,
    required this.addr,
    required this.token,
    this.goGenerate,
  });

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  List<Map<String, dynamic>> _emails = [];
  bool _loading = false;
  String? _error;
  Timer? _timer;
  DateTime? _lastFetch;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final addr = widget.addr;
    if (addr == null || addr.isEmpty) return;
    if (_loading) return;
    _loading = true;
    final d = await MailApi.instance.waitInbox(addr, token: widget.token);
    _loading = false;
    if (!mounted) return;
    setState(() {
      if (d['_status'] == 200) {
        final list = d['emails'];
        _emails = list is List
            ? list.whereType<Map<String, dynamic>>().toList()
            : [];
        _error = null;
        _lastFetch = DateTime.now();
      } else if (d['_status'] == 0) {
        _error = '网络异常';
      } else if (d['_status'] == 204) {
        _error = null;
      } else {
        _error = '错误 ${d['_status']}: ${d['error'] ?? ''}';
      }
    });
  }

  Widget _buildEmailCard(Map<String, dynamic> em) {
    final subject = (em['subject'] as String?) ?? '(无主题)';
    final from = (em['from_email'] as String?) ?? '?';
    final preview = ((em['preview_text'] as String?) ?? '').trim();
    final time = (em['created_at'] as String?) ?? '';
    final timeShort = time.length > 16 ? time.substring(0, 16) : time;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$from\n$preview',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        isThreeLine: true,
        trailing: Text(timeShort,
            style: Theme.of(context).textTheme.bodySmall),
        onTap: () => _openDetail(em),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.addr == null || widget.addr!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('还没有邮箱'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: widget.goGenerate,
              child: const Text('去生成'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _emails.isEmpty
          ? ListView(
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : Text(_error ?? '暂无邮件，5 秒后自动刷新'),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _emails.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  if (_lastFetch == null) return const SizedBox.shrink();
                  final t = _lastFetch!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '更新于 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return _buildEmailCard(_emails[i - 1]);
              },
            ),
    );
  }

  void _openDetail(Map<String, dynamic> em) {
    final id = em['id']?.toString() ?? '';
    if (id.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EmailDetailPage(emailId: id, token: widget.token),
      ),
    );
  }
}

/// 邮件详情页
class EmailDetailPage extends StatefulWidget {
  final String emailId;
  final String? token;
  const EmailDetailPage({super.key, required this.emailId, required this.token});

  @override
  State<EmailDetailPage> createState() => _EmailDetailPageState();
}

class _EmailDetailPageState extends State<EmailDetailPage> {
  Map<String, dynamic>? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d =
        await MailApi.instance.emailDetail(widget.emailId, token: widget.token);
    if (!mounted) return;
    setState(() {
      if (d['_status'] == 200) {
        _detail = d;
        _error = null;
      } else {
        _error = '加载失败: ${d['error'] ?? d['_status']}';
      }
    });
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除邮件'),
        content: const Text('确定删除这封邮件？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final d = await MailApi.instance
        .deleteEmail(widget.emailId, token: widget.token);
    if (!mounted) return;
    final st = d['_status'];
    if (st == 200 || st == 204) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: ${d['error'] ?? st}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('邮件详情'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : _detail == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(_detail!['subject'] as String? ?? '(无主题)',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('From: ${_detail!['from_email'] ?? '?'}'),
                    Text('To: ${_detail!['to_email'] ?? '?'}'),
                    Text('Time: ${_detail!['created_at'] ?? '?'}'),
                    const Divider(height: 24),
                    _buildBody(),
                  ],
                ),
    );
  }

  Widget _buildBody() {
    final text = _detail!['text'] as String?;
    final html = _detail!['html'] as String?;
    if (text != null && text.isNotEmpty) {
      return SelectableText(text);
    }
    if (html != null && html.isNotEmpty) {
      return SelectableText(_stripHtml(html));
    }
    return const Text('（空正文）');
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}