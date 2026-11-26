import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:barcode/barcode.dart' as barcode_lib;
import 'package:local_auth/local_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

void main() => runApp(const LoyaltyWalletApp());

const storage = FlutterSecureStorage();
const uuid = Uuid();

class LoyaltyCard {
  LoyaltyCard({
    required this.id,
    required this.name,
    required this.value,
    required this.format,
    this.category = 'Other',
    this.balance,
    this.favorite = false,
  });

  final String id, name, value, format, category;
  final String? balance;
  final bool favorite;

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'value': value, 'format': format,
    'category': category, 'balance': balance, 'favorite': favorite,
  };

  factory LoyaltyCard.fromJson(Map<String, dynamic> json) => LoyaltyCard(
    id: json['id'] ?? uuid.v4(),
    name: json['name'] ?? 'Card',
    value: json['value'] ?? '',
    format: json['format'] ?? 'unknown',
    category: json['category'] ?? 'Other',
    balance: json['balance'],
    favorite: json['favorite'] ?? false,
  );

  LoyaltyCard copyWith({String? balance, bool? favorite}) => LoyaltyCard(
    id: id, name: name, value: value, format: format, category: category,
    balance: balance ?? this.balance, favorite: favorite ?? this.favorite,
  );
}

class LoyaltyWalletApp extends StatelessWidget {
  const LoyaltyWalletApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Loyalty Wallet SA',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff168a70), brightness: Brightness.dark), useMaterial3: true),
    home: const WalletHome(),
  );
}

class WalletHome extends StatefulWidget {
  const WalletHome({super.key});
  @override
  State<WalletHome> createState() => _WalletHomeState();
}

class _WalletHomeState extends State<WalletHome> {
  List<LoyaltyCard> cards = [];
  bool loading = true;
  String search = '';

  @override
  void initState() { super.initState(); loadCards(); }

  Future<void> loadCards() async {
    final raw = await storage.read(key: 'wallet_cards');
    if (raw != null) {
      try { cards = (jsonDecode(raw) as List).map((e) => LoyaltyCard.fromJson(e)).toList(); } catch (_) {}
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> saveCards() async {
    await storage.write(key: 'wallet_cards', value: jsonEncode(cards.map((c) => c.toJson()).toList()));
  }

  Future<void> addScanned(String value, String format) async {
    if (!mounted) return;
    final result = await Navigator.push<LoyaltyCard>(context, MaterialPageRoute(builder: (_) => AddCardScreen(initialValue: value, initialFormat: format)));
    if (result != null) { cards.insert(0, result); await saveCards(); setState(() {}); }
  }

  Future<void> scan() async {
    final result = await Navigator.push<Map<String, String>>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (result != null && result['value'] != null) await addScanned(result['value']!, result['format'] ?? 'unknown');
  }

  List<LoyaltyCard> get filtered => cards.where((c) => c.name.toLowerCase().contains(search.toLowerCase()) || c.category.toLowerCase().contains(search.toLowerCase())).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loyalty Wallet SA'), actions: [
        IconButton(tooltip: 'Scan card', icon: const Icon(Icons.qr_code_scanner), onPressed: scan),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => addScanned('', 'manual'), icon: const Icon(Icons.add), label: const Text('Add card')),
      body: loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search your cards', border: OutlineInputBorder()), onChanged: (v) => setState(() => search = v)),
        Expanded(child: filtered.isEmpty ? const Center(child: Text('No cards yet. Scan or add your first card.')) : ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final card = filtered[index];
            return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), child: ListTile(
              leading: Icon(card.favorite ? Icons.star : Icons.card_membership, color: card.favorite ? Colors.amber : null),
              title: Text(card.name), subtitle: Text(card.category + (card.balance == null || card.balance!.isEmpty ? '' : ' • ${card.balance}')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CardDetailScreen(card: card, onUpdate: (updated) async { final i = cards.indexWhere((x) => x.id == updated.id); if (i >= 0) cards[i] = updated; await saveCards(); setState(() {}); }, onDelete: () async { cards.removeWhere((x) => x.id == card.id); await saveCards(); setState(() {}); })),
            ));
          })),
      ]),
    );
  }
}

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan loyalty code')),
    body: MobileScanner(onDetect: (capture) {
      final item = capture.barcodes.firstOrNull;
      final value = item?.rawValue;
      if (value != null && value.isNotEmpty) Navigator.pop(context, {'value': value, 'format': item!.format.name});
    }),
  );
}

class AddCardScreen extends StatefulWidget {
  const AddCardScreen({super.key, this.initialValue = '', this.initialFormat = 'unknown'});
  final String initialValue, initialFormat;
  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  late final name = TextEditingController();
  late final value = TextEditingController(text: widget.initialValue);
  late final balance = TextEditingController();
  String category = 'Other';
  @override
  void dispose() { name.dispose(); value.dispose(); balance.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add loyalty card')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Store / card name')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Category'), items: ['Groceries','Fuel','Pharmacy','Retail','Other'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) => setState(() => category = v ?? 'Other'),
      const SizedBox(height: 12),
      TextField(controller: value, decoration: const InputDecoration(labelText: 'Barcode / QR contents', helperText: 'You can scan it or enter the code manually')),
      const SizedBox(height: 12),
      TextField(controller: balance, decoration: const InputDecoration(labelText: 'Rewards balance (optional)')),
      const SizedBox(height: 24),
      FilledButton(onPressed: () {
        if (name.text.trim().isEmpty || value.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a card name and code.'))); return; }
        Navigator.pop(context, LoyaltyCard(id: uuid.v4(), name: name.text.trim(), value: value.text.trim(), format: widget.initialFormat, category: category, balance: balance.text.trim().isEmpty ? null : balance.text.trim()));
      }, child: const Text('Save card')),
    ]),
  );
}

class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.card, required this.onUpdate, required this.onDelete});
  final LoyaltyCard card;
  final Future<void> Function(LoyaltyCard) onUpdate;
  final Future<void> Function() onDelete;
  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  late LoyaltyCard card = widget.card;
  barcode_lib.Barcode get barcode {
    final f = card.format.toLowerCase();
    if (f.contains('qr')) return barcode_lib.Barcode.qrCode();
    if (f.contains('ean13')) return barcode_lib.Barcode.ean13();
    if (f.contains('ean8')) return barcode_lib.Barcode.ean8();
    if (f.contains('upca')) return barcode_lib.Barcode.upcA();
    if (f.contains('upce')) return barcode_lib.Barcode.upcE();
    if (f.contains('code128')) return barcode_lib.Barcode.code128();
    if (f.contains('code39')) return barcode_lib.Barcode.code39();
    if (f.contains('codabar')) return barcode_lib.Barcode.codabar();
    return barcode_lib.Barcode.qrCode();
  }
  Future<void> editBalance() async {
    final controller = TextEditingController(text: card.balance ?? '');
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Update rewards balance'), content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Balance')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save'))]);
    controller.dispose();
    if (result != null) { card = card.copyWith(balance: result); await widget.onUpdate(card); setState(() {}); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(card.name), actions: [IconButton(icon: Icon(card.favorite ? Icons.star : Icons.star_border), onPressed: () async { card = card.copyWith(favorite: !card.favorite); await widget.onUpdate(card); setState(() {}); })]),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Text(card.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 24),
        BarcodeWidget(barcode: barcode, data: card.value, width: 320, height: 150, drawText: true, errorBuilder: (context, error) => Text('This code format cannot be displayed.\\nCode: ${card.value}')),
        const SizedBox(height: 16),
        SelectableText(card.value, textAlign: TextAlign.center),
      ]))),
      ListTile(title: const Text('Rewards balance'), subtitle: Text(card.balance ?? 'Not set'), trailing: IconButton(icon: const Icon(Icons.edit), onPressed: editBalance)),
      ListTile(title: const Text('Card format'), subtitle: Text(card.format)),
      ListTile(title: const Text('Category'), subtitle: Text(card.category)),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: () async { await widget.onDelete(); if (mounted) Navigator.pop(context); }, icon: const Icon(Icons.delete_outline), label: const Text('Delete card')),
    ]),
  );
}

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}
class _SecurityScreenState extends State<SecurityScreen> {
  final auth = LocalAuthentication();
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Security')), body: Padding(padding: const EdgeInsets.all(16), child: FilledButton.icon(onPressed: () async {
    try { final ok = await auth.authenticate(localizedReason: 'Authenticate to protect your wallet', options: const AuthenticationOptions(biometricOnly: false)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Authentication successful' : 'Authentication cancelled'))); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Authentication unavailable: $e'))); }
  }, icon: const Icon(Icons.fingerprint), label: const Text('Test device authentication'))));
}
