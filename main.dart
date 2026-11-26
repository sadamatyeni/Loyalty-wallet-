import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LoyaltyWalletApp());
}

const storage = FlutterSecureStorage();

class LoyaltyCard {
  String id;
  String name;
  String code;
  String format;
  String balance;
  bool favourite;

  LoyaltyCard({
    required this.id,
    required this.name,
    required this.code,
    required this.format,
    this.balance = '0',
    this.favourite = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'format': format,
        'balance': balance,
        'favourite': favourite,
      };

  factory LoyaltyCard.fromJson(Map<String, dynamic> json) {
    return LoyaltyCard(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Loyalty Card',
      code: json['code'] ?? '',
      format: json['format'] ?? 'qr',
      balance: json['balance'] ?? '0',
      favourite: json['favourite'] ?? false,
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF146B4A),
        ),
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
  bool loading = true;
  bool unlocked = false;
  bool setupPin = false;
  String search = '';
  String pinHash = '';

  @override
  void initState() {
    super.initState();
    loadWallet();
  }

  Future<void> loadWallet() async {
    final savedCards = await storage.read(key: 'wallet_cards');
    final savedPin = await storage.read(key: 'wallet_pin');

    if (savedCards != null) {
      try {
        final decoded = jsonDecode(savedCards) as List;
        cards = decoded
            .map((e) => LoyaltyCard.fromJson(e))
            .toList();
      } catch (_) {
        cards = [];
      }
    }

    pinHash = savedPin ?? '';
    setupPin = pinHash.isEmpty;
    unlocked = false;

    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> saveWallet() async {
    await storage.write(
      key: 'wallet_cards',
      value: jsonEncode(cards.map((e) => e.toJson()).toList()),
    );
  }

  String hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  Future<void> savePin(String pin) async {
    pinHash = hashPin(pin);
    await storage.write(key: 'wallet_pin', value: pinHash);

    if (mounted) {
      setState(() {
        setupPin = false;
        unlocked = true;
      });
    }
  }

  Future<void> checkPin(String pin) async {
    if (hashPin(pin) == pinHash) {
      setState(() => unlocked = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN')),
      );
    }
  }

  Future<void> biometricUnlock() async {
    try {
      final auth = LocalAuthentication();
      final available = await auth.canCheckBiometrics ||
          await auth.isDeviceSupported();

      if (!available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometrics are not available on this device'),
          ),
        );
        return;
      }

      final success = await auth.authenticate(
        localizedReason: 'Unlock Loyalty Wallet',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      if (success && mounted) {
        setState(() => unlocked = true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Authentication failed: $e')),
      );
    }
  }

  Future<void> addCard({
    required String name,
    required String code,
    required String format,
  }) async {
    if (name.trim().isEmpty || code.trim().isEmpty) return;

    cards.add(
      LoyaltyCard(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.trim(),
        code: code.trim(),
        format: format,
      ),
    );

    await saveWallet();
    setState(() {});
  }

  Future<void> deleteCard(LoyaltyCard card) async {
    cards.removeWhere((c) => c.id == card.id);
    await saveWallet();
    setState(() {});
  }

  Future<void> toggleFavourite(LoyaltyCard card) async {
    card.favourite = !card.favourite;
    await saveWallet();
    setState(() {});
  }

  Future<void> editBalance(LoyaltyCard card) async {
    final controller = TextEditingController(text: card.balance);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${card.name} balance'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
          ),
          decoration: const InputDecoration(
            labelText: 'Reward balance',
            hintText: 'Enter your balance',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      card.balance = result;
      await saveWallet();
      setState(() {});
    }
  }

  Future<void> showAddCardDialog() async {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    String format = 'qr';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add loyalty card'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Card name',
                      hintText: 'e.g. Checkers Xtra Savings',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Barcode number or QR text',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: format,
                    decoration: const InputDecoration(
                      labelText: 'Barcode type',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'qr', child: Text('QR Code')),
                      DropdownMenuItem(value: 'ean13', child: Text('EAN-13')),
                      DropdownMenuItem(value: 'ean8', child: Text('EAN-8')),
                      DropdownMenuItem(value: 'upca', child: Text('UPC-A')),
                      DropdownMenuItem(value: 'upce', child: Text('UPC-E')),
                      DropdownMenuItem(
                        value: 'code128',
                        child: Text('Code 128'),
                      ),
                      DropdownMenuItem(
                        value: 'code39',
                        child: Text('Code 39'),
                      ),
                      DropdownMenuItem(value: 'itf', child: Text('ITF')),
                      DropdownMenuItem(
                        value: 'codabar',
                        child: Text('Codabar'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => format = value);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save card'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      await addCard(
        name: nameController.text,
        code: codeController.text,
        format: format,
      );
    }
  }

  Future<void> scanCard() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanPage(),
      ),
    );

    if (result != null) {
      final code = result['code'] ?? '';
      final format = result['format'] ?? 'qr';

      final nameController = TextEditingController();

      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Name your card'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. Pick n Pay Smart Shopper',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                nameController.text,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (name != null && name.trim().isNotEmpty) {
        await addCard(
          name: name,
          code: code,
          format: format,
        );
      }
    }
  }

  bw.Barcode barcodeFor(String format) {
    final f = format.toLowerCase();

    if (f.contains('qr')) return bw.Barcode.qrCode();
    if (f.contains('ean13')) return bw.Barcode.ean13();
    if (f.contains('ean8')) return bw.Barcode.ean8();
    if (f.contains('upca')) return bw.Barcode.upcA();
    if (f.contains('upce')) return bw.Barcode.upcE();
    if (f.contains('code128')) return bw.Barcode.code128();
    if (f.contains('code39')) return bw.Barcode.code39();
    if (f.contains('itf')) return bw.Barcode.itf();
    if (f.contains('codabar')) return bw.Barcode.codabar();

    return bw.Barcode.qrCode();
  }

  List<LoyaltyCard> get filteredCards {
    final q = search.toLowerCase();

    return cards.where((card) {
      return card.name.toLowerCase().contains(q) ||
          card.code.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        if (a.favourite == b.favourite) {
          return a.name.compareTo(b.name);
        }
        return a.favourite ? -1 : 1;
      });
  }

  Widget pinScreen() {
    final controller = TextEditingController();

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.wallet,
                size: 80,
                color: Color(0xFF146B4A),
              ),
              const SizedBox(height: 16),
              const Text(
                'Loyalty Wallet SA',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                setupPin ? 'Create a PIN to protect your cards' : 'Wallet locked',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: '4–6 digit PIN',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final pin = controller.text;

                    if (pin.length < 4) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('PIN must be at least 4 digits'),
                        ),
                      );
                      return;
                    }

                    if (setupPin) {
                      savePin(pin);
                    } else {
                      checkPin(pin);
                    }
                  },
                  child: Text(setupPin ? 'Create PIN' : 'Unlock'),
                ),
              ),
              if (!setupPin) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: biometricUnlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Use device authentication'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!unlocked) {
      return pinScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loyalty Wallet SA'),
        actions: [
          IconButton(
            tooltip: 'Lock wallet',
            icon: const Icon(Icons.lock),
            onPressed: () => setState(() => unlocked = false),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) => setState(() => search = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search loyalty cards',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Expanded(
            child: filteredCards.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.credit_card,
                          size: 70,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 12),
                        const Text('No loyalty cards yet'),
                        const SizedBox(height: 8),
                        const Text('Scan a card or add one manually'),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: scanCard,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan card'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    itemCount: filteredCards.length,
                    itemBuilder: (context, index) {
                      final card = filteredCards[index];

                      return Card(
                        child: ListTile(
                          leading: Icon(
                            card.favourite
                                ? Icons.star
                                : Icons.card_membership,
                            color: card.favourite
                                ? Colors.amber
                                : Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(card.name),
                          subtitle: Text('Balance: ${card.balance}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'fav') {
                                toggleFavourite(card);
                              } else if (value == 'balance') {
                                editBalance(card);
                              } else if (value == 'delete') {
                                deleteCard(card);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'fav',
                                child: Text(
                                  card.favourite
                                      ? 'Remove favourite'
                                      : 'Add favourite',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'balance',
                                child: Text('Edit balance'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete card'),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CardDisplayPage(
                                  card: card,
                                  barcode: barcodeFor(card.format),
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
            onPressed: showAddCardDialog,
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'scan',
            onPressed: scanCard,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan card'),
          ),
        ],
      ),
    );
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan loyalty card')),
      body: MobileScanner(
        onDetect: (capture) {
          if (scanned) return;

          final barcode = capture.barcodes.firstOrNull;
          final value = barcode?.rawValue;

          if (value == null || value.isEmpty) return;

          scanned = true;

          Navigator.pop(
            context,
            {
              'code': value,
              'format': barcode!.format.name,
            },
          );
        },
      ),
    );
  }
}

class CardDisplayPage extends StatelessWidget {
  final LoyaltyCard card;
  final bw.Barcode barcode;

  const CardDisplayPage({
    super.key,
    required this.card,
    required this.barcode,
  });

  @override
  Widget build(BuildContext context) {
    final isQr = card.format.toLowerCase().contains('qr');

    return Scaffold(
      appBar: AppBar(title: Text(card.name)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  card.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: bw.BarcodeWidget(
                    barcode: barcode,
                    data: card.code,
                    width: isQr ? 260 : 320,
                    height: isQr ? 260 : 160,
                    drawText: !isQr,
                  ),
                ),
                const SizedBox(height: 24),
                SelectableText(
                  card.code,
                  style: const TextStyle(fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Balance: ${card.balance}',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Increase screen brightness for easier scanning.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: card.code),
                    );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy code'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
