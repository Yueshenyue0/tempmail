import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../mail_api.dart';
import '../native_bridge.dart';

/// Tab1: 生成邮箱（随机/自定义）
class GeneratorPage extends StatefulWidget {
  final String? addr;
  final String? token;
  final ValueChanged<String> onAddressCreated;
  const GeneratorPage({
    super.key,
    required this.addr,
    required this.token,
    required this.onAddressCreated,
  });

  @override
  State<GeneratorPage> createState() => _GeneratorPageState();
}

class _GeneratorPageState extends State<GeneratorPage> {
  final _customCtrl = TextEditingController();
  String? _selectedDomain;

  @override
  void initState() {
    super.initState();
    final pool = NativeCore.instance.domainPool();
    _selectedDomain = pool.isNotEmpty ? pool.first : 'uqu.me';
  }

  void _genRandom() {
    final local = NativeCore.instance.randLocal();
    final addr = '$local@$_selectedDomain';
    widget.onAddressCreated(addr);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已生成: $addr')),
    );
  }

  void _useCustom() {
    final local = _customCtrl.text.trim().toLowerCase();
    if (local.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入邮箱前缀')),
      );
      return;
    }
    if (!RegExp(r'^[a-z0-9._-]{2,20}$').hasMatch(local)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('前缀规则: 2-20位小写字母/数字/._-')),
      );
      return;
    }
    final addr = '$local@$_selectedDomain';
    widget.onAddressCreated(addr);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换到: $addr')),
    );
  }

  void _copy() {
    if (widget.addr == null) return;
    Clipboard.setData(ClipboardData(text: widget.addr!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pool = NativeCore.instance.domainPool();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 当前邮箱卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前邮箱', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SelectableText(
                  widget.addr ?? '（未生成）',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy),
                      label: const Text('复制'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _genRandom,
                      icon: const Icon(Icons.casino),
                      label: const Text('随机生成'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 随机生成
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('随机邮箱', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('选域名后一键生成随机前缀，无需创建，邮件到达即缓冲',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in pool)
                      ChoiceChip(
                        label: Text(d),
                        selected: _selectedDomain == d,
                        onSelected: (_) => setState(() => _selectedDomain = d),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _genRandom,
                  child: const Text('生成随机邮箱'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 自定义
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('自定义邮箱', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('输入前缀，配合上方域名使用',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _customCtrl,
                  decoration: InputDecoration(
                    hintText: '例如 eri01',
                    border: const OutlineInputBorder(),
                    suffixText: '@$_selectedDomain',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9._-]')),
                  ],
                  onSubmitted: (_) => _useCustom(),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _useCustom,
                  child: const Text('使用该邮箱'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 设置页：token 管理
class SettingsPage extends StatefulWidget {
  final String? token;
  final ValueChanged<String> onTokenSaved;
  const SettingsPage({super.key, required this.token, required this.onTokenSaved});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.token ?? '');
  bool _checking = false;
  String? _status;

  Future<void> _save() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) {
      await MailApi.instance.clearToken();
      widget.onTokenSaved('');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已清除 token')));
      }
      return;
    }
    setState(() { _checking = true; _status = null; });
    // 验证 token: 列 tokens 接口
    final d = await MailApi.instance.listDomains(token: t);
    final ok = d['_status'] == 200;
    setState(() {
      _checking = false;
      _status = ok ? 'token 有效' : '无效: ${d['error'] ?? d['_status']}';
    });
    if (ok) {
      await MailApi.instance.saveToken(t);
      widget.onTokenSaved(t);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('API Token', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('mail.cx Dashboard -> Tokens 获取，混淆存储在本机',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'tm_live_...',
              border: OutlineInputBorder(),
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(_status!, style: TextStyle(
                color: _status!.contains('有效') ? Colors.green : Colors.red)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _checking ? null : _save,
            child: Text(_checking ? '验证中...' : '保存并验证'),
          ),
        ],
      ),
    );
  }
}