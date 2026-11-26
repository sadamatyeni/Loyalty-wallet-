import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const LoyaltyWalletApp());
}

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

  factory LoyaltyCard.fromJson(Map<String, dynamic> j) {
    return LoyaltyCard(
      id: j['id'] ?? uuid.v4(),
      name: j['name'] ?? 'Loyalty card',
      value: j['value'] ?? '',
      format: j['format'] ?? 'QR',
      balance: j['balance'] ?? '',
      favorite: j['favorite'] ?? false,
    );
  }
}

class LoyaltyWalletApp extends StatelessWidget {
  const LoyaltyWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loyalty Wallet SA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const WalletHome(),
    );
  }
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
                  Map<String, dynamic>.from(e),
                ))
            .toList();
      } catch (_) {
        cards = [];
      }
    }

    locked = pinHash != null;

    if (mounted) {
      setState(() => loading = false);
    }

    if (locked) {
      _unlock();
    }
  }

  Future<void> _save() async {
    await storage.write(
      key: 'wallet_cards',
      value: jsonEncode(cards.map((c) => c.toJson()).toList()),
    );

    if (mounted) setState(() {});
  }

  Future<String?> _pinDialog(String title) async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
              if (controller.text.length >= 4 &&
                  controller.text.length <= 8) {
                Navigator.pop(ctx, controller.text);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  String _hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  Future<void> _setPin() async {
    final pin = await _pinDialog('Create a wallet PIN');
    if (pin == null) return;

    await storage.write(
      key: 'wallet_pin_hash',
      value: _hashPin(pin),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN security enabled')),
      );
    }
  }

  Future<void> _unlock() async {
    final auth = LocalAuthentication();

    try {
      final canAuthenticate =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();

      if (canAuthenticate) {
        final success = await auth.authenticate(
          localizedReason: 'Unlock your Loyalty Wallet',
          options: const AuthenticationOptions(
            biometricOnly: false,
          ),
        );

        if (success) {
          if (mounted) setState(() => locked = false);
          return;
        }
      }
    } catch (_) {}

    final pin = await _pinDialog('Enter your wallet PIN');
    final savedHash = await storage.read(key: 'wallet_pin_hash');

    if (pin != null && savedHash == _hashPin(pin)) {
      if (mounted) setState(() => locked = false);
    } else if (pin != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN')),
      );
    }
  }

  Future<String?> _textDialog(
    String title, {
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  Future<void> _scan() async {
    final capture = await Navigator.push<BarcodeCapture>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanPage(),
      ),
    );

    if (capture == null || capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first;
    final value = barcode.rawValue;

    if (value == null || value.isEmpty) return;

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
        value: value,
        format: barcode.format.name,
      ),
    );

    await _save();
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
    final balance = await _textDialog(
      'Rewards balance',
      initial: card.balance,
    );

    if (balance == null) return;

    card.balance = balance;
    await _save();
  }

  Future<void> _delete(LoyaltyCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete card?'),
        content: Text('Remove ${card.name} from your wallet?'),
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

    if (confirmed == true) {
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
        .where((c) =>
            c.name.toLowerCase().contains(search.toLowerCase()))
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
                      final card = shown[i];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.card_membership),
                          title: Text(card.name),
                          subtitle: Text(
                            card.balance.isEmpty
                                ? card.format
                                : 'Balance: ${card.balance}',
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              card.favorite
                                  ? Icons.star
                                  : Icons.star_border,
                            ),
                            onPressed: () {
                              card.favorite = !card.favorite;
                              _save();
                            },
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CardDetail(
                                  card: card,
                                  onBalance: () => _editBalance(card),
                                  onDelete: () => _delete(card),
                                ),
                              ),
                            );
                          },
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
}import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const LoyaltyWalletApp());
}

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

  factory LoyaltyCard.fromJson(Map<String, dynamic> j) {
    return LoyaltyCard(
      id: j['id'] ?? uuid.v4(),
      name: j['name'] ?? 'Loyalty card',
      value: j['value'] ?? '',
      format: j['format'] ?? 'QR',
      balance: j['balance'] ?? '',
      favorite: j['favorite'] ?? false,
    );
  }
}

class LoyaltyWalletApp extends StatelessWidget {
  const LoyaltyWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loyalty Wallet SA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const WalletHome(),
    );
  }
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
                  Map<String, dynamic>.from(e),
                ))
            .toList();
      } catch (_) {
        cards = [];
      }
    }

    locked = pinHash != null;

    if (mounted) {
      setState(() => loading = false);
    }

    if (locked) {
      _unlock();
    }
  }

  Future<void> _save() async {
    await storage.write(
      key: 'wallet_cards',
      value: jsonEncode(cards.map((c) => c.toJson()).toList()),
    );

    if (mounted) setState(() {});
  }

  Future<String?> _pinDialog(String title) async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
              if (controller.text.length >= 4 &&
                  controller.text.length <= 8) {
                Navigator.pop(ctx, controller.text);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  String _hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  Future<void> _setPin() async {
    final pin = await _pinDialog('Create a wallet PIN');
    if (pin == null) return;

    await storage.write(
      key: 'wallet_pin_hash',
      value: _hashPin(pin),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN security enabled')),
      );
    }
  }

  Future<void> _unlock() async {
    final auth = LocalAuthentication();

    try {
      final canAuthenticate =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();

      if (canAuthenticate) {
        final success = await auth.authenticate(
          localizedReason: 'Unlock your Loyalty Wallet',
          options: const AuthenticationOptions(
            biometricOnly: false,
          ),
        );

        if (success) {
          if (mounted) setState(() => locked = false);
          return;
        }
      }
    } catch (_) {}

    final pin = await _pinDialog('Enter your wallet PIN');
    final savedHash = await storage.read(key: 'wallet_pin_hash');

    if (pin != null && savedHash == _hashPin(pin)) {
      if (mounted) setState(() => locked = false);
    } else if (pin != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN')),
      );
    }
  }

  Future<String?> _textDialog(
    String title, {
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  Future<void> _scan() async {
    final capture = await Navigator.push<BarcodeCapture>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanPage(),
      ),
    );

    if (capture == null || capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first;
    final value = barcode.rawValue;

    if (value == null || value.isEmpty) return;

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
        value: value,
        format: barcode.format.name,
      ),
    );

    await _save();
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
    final balance = await _textDialog(
      'Rewards balance',
      initial: card.balance,
    );

    if (balance == null) return;

    card.balance = balance;
    await _save();
  }

  Future<void> _delete(LoyaltyCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete card?'),
        content: Text('Remove ${card.name} from your wallet?'),
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

    if (confirmed == true) {
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
        .where((c) =>
            c.name.toLowerCase().contains(search.toLowerCase()))
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
                      final card = shown[i];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.card_membership),
                          title: Text(card.name),
                          subtitle: Text(
                            card.balance.isEmpty
                                ? card.format
                                : 'Balance: ${card.balance}',
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              card.favorite
                                  ? Icons.star
                                  : Icons.star_border,
                            ),
                            onPressed: () {
                              card.favorite = !card.favorite;
                              _save();
                            },
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CardDetail(
                                  card: card,
                                  onBalance: () => _editBalance(card),
                                  onDelete: () => _delete(card),
                                ),
                              ),
                            );
                          },
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
}import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const LoyaltyWalletApp());
}

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

  factory LoyaltyCard.fromJson(Map<String, dynamic> j) {
    return LoyaltyCard(
      id: j['id'] ?? uuid.v4(),
      name: j['name'] ?? 'Loyalty card',
      value: j['value'] ?? '',
      format: j['format'] ?? 'QR',
      balance: j['balance'] ?? '',
      favorite: j['favorite'] ?? false,
    );
  }
}

class LoyaltyWalletApp extends StatelessWidget {
  const LoyaltyWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loyalty Wallet SA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const WalletHome(),
    );
  }
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
                  Map<String, dynamic>.from(e),
                ))
            .toList();
      } catch (_) {
        cards = [];
      }
    }

    locked = pinHash != null;

    if (mounted) {
      setState(() => loading = false);
    }

    if (locked) {
      _unlock();
    }
  }

  Future<void> _save() async {
    await storage.write(
      key: 'wallet_cards',
      value: jsonEncode(cards.map((c) => c.toJson()).toList()),
    );

    if (mounted) setState(() {});
  }

  Future<String?> _pinDialog(String title) async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
              if (controller.text.length >= 4 &&
                  controller.text.length <= 8) {
                Navigator.pop(ctx, controller.text);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  String _hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  Future<void> _setPin() async {
    final pin = await _pinDialog('Create a wallet PIN');
    if (pin == null) return;

    await storage.write(
      key: 'wallet_pin_hash',
      value: _hashPin(pin),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN security enabled')),
      );
    }
  }

  Future<void> _unlock() async {
    final auth = LocalAuthentication();

    try {
      final canAuthenticate =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();

      if (canAuthenticate) {
        final success = await auth.authenticate(
          localizedReason: 'Unlock your Loyalty Wallet',
          options: const AuthenticationOptions(
            biometricOnly: false,
          ),
        );

        if (success) {
          if (mounted) setState(() => locked = false);
          return;
        }
      }
    } catch (_) {}

    final pin = await _pinDialog('Enter your wallet PIN');
    final savedHash = await storage.read(key: 'wallet_pin_hash');

    if (pin != null && savedHash == _hashPin(pin)) {
      if (mounted) setState(() => locked = false);
    } else if (pin != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN')),
      );
    }
  }

  Future<String?> _textDialog(
    String title, {
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  Future<void> _scan() async {
    final capture = await Navigator.push<BarcodeCapture>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanPage(),
      ),
    );

    if (capture == null || capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first;
    final value = barcode.rawValue;

    if (value == null || value.isEmpty) return;

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
        value: value,
        format: barcode.format.name,
      ),
    );

    await _save();
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
    final balance = await _textDialog(
      'Rewards balance',
      initial: card.balance,
    );

    if (balance == null) return;

    card.balance = balance;
    await _save();
  }

  Future<void> _delete(LoyaltyCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete card?'),
        content: Text('Remove ${card.name} from your wallet?'),
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

    if (confirmed == true) {
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
        .where((c) =>
            c.name.toLowerCase().contains(search.toLowerCase()))
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
                      final card = shown[i];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.card_membership),
                          title: Text(card.name),
                          subtitle: Text(
                            card.balance.isEmpty
                                ? card.format
                                : 'Balance: ${card.balance}',
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              card.favorite
                                  ? Icons.star
                                  : Icons.star_border,
                            ),
                            onPressed: () {
                              card.favorite = !card.favorite;
                              _save();
                            },
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CardDetail(
                                  card: card,
                                  onBalance: () => _editBalance(card),
                                  onDelete: () => _delete(card),
                                ),
                              ),
                            );
                          },
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
