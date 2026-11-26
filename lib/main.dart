import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    this.balance = '',
    this.favorite = false,
  });

  final String id;
  String name;
  String value;
  String format;
  String balance;
  bool favorite;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'value': value,
    'format': format,
    'balance': balance,
    'favorite': favorite,
  };

  factory LoyaltyCard.fromJson(Map<String, dynamic> j) => LoyaltyCard(
    id: j['id'] ?? uuid.v4(),
    name: j['name'] ?? 'Loyalty card',
    value: j['value'] ?? '',
    format: j['format'] ?? 'QR',
    balance: j['balance'] ?? '',
    favorite: j['favorite'] ?? false,
  );
}

class LoyaltyWalletApp extends StatelessWidget {
  const LoyaltyWalletApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Loyalty Wallet SA',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: Colors.teal,
      useMaterial3: true,
    ),
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
  bool locked = false;
  bool loading = true;
  String search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await storage.read(key: 'wallet_cards');
    final pinHash = await storage.read(key: 'wallet_pin_hash');

    if (raw != null) {
      try {
        cards = (jsonDecode(raw) as List)
            .map((e) => LoyaltyCard.fromJson(
                Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }

    if (pinHash != null) locked = true;

    setState(() => loading = false);

    if (locked) _unlock();
  }

  Future<void> _save() async {
    await storage.write(
      key: 'wallet_cards',
      value: jsonEncode(cards.map((c) => c.toJson()).toList()),
    );

    if (mounted) setState(() {});
  }

  Future<void> _setPin() async {
    final pin = await _pinDialog('Create a PIN');

    if (pin == null || pin.length < 4) return;

    final hash = sha256.convert(utf8.encode(pin)).toString();

    await storage.write(key: 'wallet_pin_hash', value: hash);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN security enabled')),
      );
    }
  }

  Future<String?> _pinDialog(String title) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: '4–8 digit PIN',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final p = controller.text;
                if (p.length >= 4 && p.length <= 8) {
                  Navigator.pop(ctx, p);
                }
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _unlock() async {
    final auth = LocalAuthentication();

    try {
      final can = await auth.canCheckBiometrics ||
          await auth.isDeviceSupported();

      if (can) {
        final ok = await auth.authenticate(
          localizedReason: 'Unlock your Loyalty Wallet',
          options: const AuthenticationOptions(
            biometricOnly: false,
          ),
        );

        if (ok) {
          if (mounted) setState(() => locked = false);
          return;
        }
      }
    } catch (_) {}

    final pin = await _pinDialog('Enter your wallet PIN');
    final stored = await storage.read(key: 'wallet_pin_hash');

    if (pin != null &&
        stored == sha256.convert(utf8.encode(pin)).toString()) {
      if (mounted) setState(() => locked = false);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN')),
      );
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.push<BarcodeCapture>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );

    if (result == null || result.barcodes.isEmpty) return;

    final barcode = result.barcodes.first;
    final raw = barcode.rawValue;

    if (raw == null || raw.isEmpty) return;

    final format = barcode.format.name;

    final name = await _textDialog(
      'Card name',
      initial: 'New loyalty card',
    );

    if (name == null || name.trim().isEmpty) return;

    cards.insert(
      0,
      LoyaltyCard(
        id: uuid.v4(),
        name: name.trim(),
        value: raw,
        format: format,
      ),
    );

    await _save();
  }

  Future<String?> _textDialog(
    String title, {
    String initial = '',
  }) async {
    final c = TextEditingController(text: initial);

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _addManual() async {
    final name = await _textDialog('Card name');

    if (name == null || name.trim().isEmpty) return;

    final value = await _textDialog('Barcode / QR value');

    if (value == null || value.trim().isEmpty) return;

    cards.insert(
      0,
      LoyaltyCard(
        id: uuid.v4(),
        name: name.trim(),
        value: value.trim(),
        format: 'QR',
      ),
    );

    await _save();
  }

  Future<void> _editBalance(LoyaltyCard card) async {
    final b = await _textDialog(
      'Rewards balance',
      initial: card.balance,
    );

    if (b == null) return;

    card.balance = b;
    await _save();
  }

  Future<void> _delete(LoyaltyCard card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete card?'),
        content: Text('Remove ${card.name} from this wallet?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      cards.removeWhere((c) => c.id == card.id);
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (locked) {
      return Scaffold(
        body: Center(
          child: FilledButton.icon(
            onPressed: _unlock,
            icon: const Icon(Icons.lock_open),
            label: const Text('Unlock wallet'),
          ),
        ),
      );
    }

    final shown = cards
        .where((c) => c.name.toLowerCase().contains(search.toLowerCase()))
        .toList()
      ..sort((a, b) =>
          (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loyalty Wallet SA'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Set PIN',
            onPressed: _setPin,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => search = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search cards',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      cards.isEmpty
                          ? 'No cards yet. Scan your first card!'
                          : 'No matches',
                    ),
                  )
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final c = shown[i];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.card_membership),
                          title: Text(c.name),
                          subtitle: c.balance.isEmpty
                              ? Text(c.format)
                              : Text('Balance: ${c.balance}'),
                          trailing: IconButton(
                            icon: Icon(
                              c.favorite
                                  ? Icons.star
                                  : Icons.star_border,
                            ),
                            onPressed: () {
                              c.favorite = !c.favorite;
                              _save();
                            },
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CardDetail(
                                card: c,
                                onBalance: () => _editBalance(c),
                                onDelete: () => _delete(c),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'manual',
            onPressed: _addManual,
            child: const Icon(Icons.edit),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'scan',
            onPressed: _scan,
            child: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
    );
  }
}

class ScanPage extends StatelessWidget {
  const ScanPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan loyalty card')),
    body: MobileScanner(
      onDetect: (capture) {
        if (capture.barcodes.isNotEmpty) {
          Navigator.pop(context, capture);
        }
      },
    ),
  );
}

class CardDetail extends StatelessWidget {
  const CardDetail({
    super.key,
    required this.card,
    required this.onBalance,
    required this.onDelete,
  });

  final LoyaltyCard card;
  final VoidCallback onBalance;
  final VoidCallback onDelete;

  Barcode _barcode() {
    final f = card.format.toLowerCase();

    try {
      if (f.contains('qr')) return Barcode.qrCode();
      if (f.contains('ean13')) return Barcode.ean13();
      if (f.contains('ean8')) return Barcode.ean8();
      if (f.contains('upca')) return Barcode.upcA();
      if (f.contains('upce')) return Barcode.upcE();
      if (f.contains('code128')) return Barcode.code128();
      if (f.contains('code39')) return Barcode.code39();
      if (f.contains('itf')) return Barcode.itf();
      if (f.contains('codabar')) return Barcode.codabar();
    } catch (_) {}

    return Barcode.qrCode();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(card.name),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: BarcodeWidget(
            barcode: _barcode(),
            data: card.value,
            width: 300,
            height: 220,
            drawText: true,
            errorBuilder: (_, __) => const Text(
              'Cannot render this code format',
            ),
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(
          card.value,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ListTile(
          title: const Text('Rewards balance'),
          subtitle: Text(
            card.balance.isEmpty ? 'Not set' : card.balance,
          ),
          trailing: const Icon(Icons.edit),
          onTap: onBalance,
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'If the original barcode format is unsupported, '
            'this display may not match the retailer’s original code. '
            'Test it at the store before relying on it.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}
