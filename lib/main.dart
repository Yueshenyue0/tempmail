import 'package:flutter/material.dart';
import 'mail_api.dart';
import 'pages/generator_page.dart';
import 'pages/inbox_page.dart';

void main() {
  runApp(const TempMailApp());
}

class TempMailApp extends StatelessWidget {
  const TempMailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TempMail',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  String? _token;
  String? _addr;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final token = await MailApi.instance.loadToken();
    final addr = await MailApi.instance.loadAddress();
    if (!mounted) return;
    setState(() {
      _token = token;
      _addr = addr;
    });
  }

  void _setAddress(String addr) {
    setState(() => _addr = addr);
    MailApi.instance.saveAddress(addr);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_addr ?? 'TempMail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => SettingsPage(
                  token: _token,
                  onTokenSaved: (t) {
                    setState(() => _token = t);
                  },
                ),
              ));
              final token = await MailApi.instance.loadToken();
              if (mounted) setState(() => _token = token);
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          GeneratorPage(
            addr: _addr,
            token: _token,
            onAddressCreated: _setAddress,
          ),
          InboxPage(
            addr: _addr,
            token: _token,
            goGenerate: () => setState(() => _tab = 0),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.alternate_email), label: '生成邮箱'),
          NavigationDestination(icon: Icon(Icons.inbox), label: '收件箱'),
        ],
      ),
    );
  }
}