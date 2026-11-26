import 'dart:convert';
import 'dart:math';
import 'package:barcode/barcode.dart' as barcode_lib;
import 'package:barcode_widget/barcode_widget.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

void main() => runApp(const LoyaltyWalletApp());

const storage = FlutterSecureStorage();
const uuid = Uuid();

class LoyaltyCard {
  LoyaltyCard({required this.id, required this.name, required this.value,
    required this.format, required this.category, this.balance, this.balanceLabel='Rewards',
    this.favourite=false});
  final String id, name, value, format, category;
  double? balance;
  String balanceLabel;
  bool favourite;
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'value':value,'format':format,
    'category':category,'balance':balance,'balanceLabel':balanceLabel,'favourite':favourite};
  factory LoyaltyCard.fromJson(Map<String,dynamic> j)=>LoyaltyCard(
    id:j['id'],name:j['name'],value:j['value'],format:j['format']??'unknown',
    category:j['category']??'Other',balance:(j['balance'] as num?)?.toDouble(),
    balanceLabel:j['balanceLabel']??'Rewards',favourite:j['favourite']??false);
}

class LoyaltyWalletApp extends StatefulWidget {
  const LoyaltyWalletApp({super.key});
  @override State<LoyaltyWalletApp> createState()=>_LoyaltyWalletAppState();
}
class _LoyaltyWalletAppState extends State<LoyaltyWalletApp> {
  bool locked=false, securityEnabled=false, ready=false;
  @override void initState(){super.initState();_init();}
  Future<void> _init() async {
    securityEnabled=await storage.read(key:'security_enabled')=='true';
    if(securityEnabled) locked=true;
    setState(()=>ready=true);
  }
  @override Widget build(BuildContext context)=>MaterialApp(
    title:'Loyalty Wallet SA',debugShowCheckedModeBanner:false,
    theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff68d7a5),brightness:Brightness.dark),useMaterial3:true,scaffoldBackgroundColor:const Color(0xff101820)),
    home:!ready?const Scaffold(body:Center(child:CircularProgressIndicator())):
      locked?UnlockScreen(onUnlocked:(){setState(()=>locked=false);}):
      WalletHome(onLock:()=>setState(()=>locked=securityEnabled),onSecurityChanged:(v){setState(()=>securityEnabled=v);}),
  );
}

class WalletHome extends StatefulWidget {
  const WalletHome({super.key,required this.onLock,required this.onSecurityChanged});
  final VoidCallback onLock; final ValueChanged<bool> onSecurityChanged;
  @override State<WalletHome> createState()=>_WalletHomeState();
}
class _WalletHomeState extends State<WalletHome> {
  List<LoyaltyCard> cards=[]; bool loading=true; String query='';
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{
    final raw=await storage.read(key:'wallet_cards');
    if(raw!=null){try{cards=(jsonDecode(raw) as List).map((e)=>LoyaltyCard.fromJson(e)).toList();}catch(_){}}
    setState(()=>loading=false);
  }
  Future<void> _save()async=>storage.write(key:'wallet_cards',value:jsonEncode(cards.map((c)=>c.toJson()).toList()));
  Future<void> _add({String? scannedValue,String? scannedFormat})async{
    final result=await Navigator.push<LoyaltyCard>(context,MaterialPageRoute(builder:(_)=>AddCardScreen(prefill:scannedValue,format:scannedFormat)));
    if(result!=null){cards.insert(0,result);await _save();setState((){});}
  }
  List<LoyaltyCard> get filtered=>cards.where((c)=>c.name.toLowerCase().contains(query)||c.category.toLowerCase().contains(query)).toList()..sort((a,b)=>a.favourite==b.favourite?0:(a.favourite?-1:1));
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Loyalty Wallet SA',style:TextStyle(fontWeight:FontWeight.bold)),actions:[
      IconButton(tooltip:'Security settings',icon:const Icon(Icons.fingerprint),onPressed:()=>_securitySettings()),
      IconButton(tooltip:'Lock now',icon:const Icon(Icons.lock_outline),onPressed:widget.onLock),
    ]),
    floatingActionButton:FloatingActionButton.extended(onPressed:()=>_add(),icon:const Icon(Icons.add_card),label:const Text('Add card')),
    body:loading?const Center(child:CircularProgressIndicator()):Padding(padding:const EdgeInsets.all(16),child:Column(children:[
      TextField(onChanged:(v)=>setState(()=>query=v.toLowerCase()),decoration:InputDecoration(hintText:'Search your cards',prefixIcon:const Icon(Icons.search),filled:true,fillColor:const Color(0xff1a2833),border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:BorderSide.none))),
      const SizedBox(height:16),
      Expanded(child:filtered.isEmpty?Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.wallet_outlined,size:58,color:Colors.white38),const SizedBox(height:10),Text(cards.isEmpty?'Your wallet is empty':'No matching cards',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:6),const Text('Scan or add a loyalty card to begin.',style:TextStyle(color:Colors.white60))])):GridView.builder(itemCount:filtered.length,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,crossAxisSpacing:12,mainAxisSpacing:12,childAspectRatio:.92),itemBuilder:(context,i){final c=filtered[i];return CardTile(card:c,onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CardDetails(card:c,onChanged:()async{await _save();setState((){});},onDelete:(){cards.removeWhere((x)=>x.id==c.id);_save();setState((){});Navigator.pop(context);})),onFav:(){c.favourite=!c.favourite;_save();setState((){});});})),
      const SizedBox(height:4),Text('${cards.length} saved card${cards.length==1?'':'s'} • Stored encrypted on this device',style:const TextStyle(color:Colors.white54,fontSize:12))
    ]))),
  );
  Future<void> _securitySettings()async{
    final enabled=await storage.read(key:'security_enabled')=='true';
    if(enabled){await storage.write(key:'security_enabled',value:'false');await storage.delete(key:'pin_hash');await storage.delete(key:'pin_salt');widget.onSecurityChanged(false);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('App lock disabled')));return;}
    final pin=await showPinSetup(context);
    if(pin==null)return;
    final salt=Random.secure().nextInt(1<<31).toString();
    await storage.write(key:'pin_salt',value:salt);
    await storage.write(key:'pin_hash',value:sha256.convert(utf8.encode('$salt:$pin')).toString());
    await storage.write(key:'security_enabled',value:'true');
    widget.onSecurityChanged(true);
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('PIN protection enabled. Biometrics can be used to unlock when available.')));
  }
}

class CardTile extends StatelessWidget{
  const CardTile({super.key,required this.card,required this.onTap,required this.onFav});
  final LoyaltyCard card;final VoidCallback onTap,onFav;
  @override Widget build(BuildContext context){
    final colors=card.category=='Fuel'?const [Color(0xff1f5d91),Color(0xff15385a)]:card.category=='Pharmacy'?const [Color(0xff25875b),Color(0xff15533d)]:const [Color(0xff235e4b),Color(0xff153c31)];
    return InkWell(onTap:onTap,borderRadius:BorderRadius.circular(20),child:Ink(decoration:BoxDecoration(gradient:LinearGradient(colors:colors),borderRadius:BorderRadius.circular(20)),child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Container(width:38,height:38,decoration:BoxDecoration(color:Colors.white.withValues(alpha:.15),borderRadius:BorderRadius.circular(12)),child:Center(child:Text(card.name.isNotEmpty?card.name[0].toUpperCase():'?',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18)))),const Spacer(),IconButton(onPressed:onFav,visualDensity:VisualDensity.compact,icon:Icon(card.favourite?Icons.star:Icons.star_border,color:Colors.white))]),
      const SizedBox(height:8),Text(card.name,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
      Text(card.category,style:const TextStyle(color:Colors.white70,fontSize:12)),
      const Spacer(),
      if(card.balance!=null)Text('${card.balanceLabel}: ${card.balance!.toStringAsFixed(2)}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:14),maxLines:1,overflow:TextOverflow.ellipsis),
      Row(children:[const Icon(Icons.qr_code_2,size:16),const SizedBox(width:5),Text(card.format.toUpperCase(),style:const TextStyle(fontSize:11,color:Colors.white70))])
    ]))));
  }
}

class AddCardScreen extends StatefulWidget{
  const AddCardScreen({super.key,this.prefill,this.format});
  final String? prefill,format;
  @override State<AddCardScreen> createState()=>_AddCardScreenState();
}
class _AddCardScreenState extends State<AddCardScreen>{
  final name=TextEditingController(),value=TextEditingController(),balance=TextEditingController(),balanceLabel=TextEditingController(text:'Rewards');
  String category='Shopping',format='QR';
  bool scanning=false;
  @override void initState(){super.initState();value.text=widget.prefill??'';format=widget.format??'QR';}
  @override void dispose(){name.dispose();value.dispose();balance.dispose();balanceLabel.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Add loyalty card')),body:ListView(padding:const EdgeInsets.all(18),children:[
    TextField(controller:name,decoration:const InputDecoration(labelText:'Store / programme name',hintText:'e.g. Clicks ClubCard')),
    const SizedBox(height:12),TextField(controller:value,decoration:const InputDecoration(labelText:'Barcode / QR data',hintText:'Scan or type card number')),
    const SizedBox(height:8),OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ScanScreen(onScan:(raw,f){value.text=raw;format=f;Navigator.pop(context);setState((){});}))),icon:const Icon(Icons.camera_alt),label:const Text('Scan barcode or QR')),
    const SizedBox(height:12),DropdownButtonFormField<String>(value:category,decoration:const InputDecoration(labelText:'Category'),items:['Shopping','Fuel','Pharmacy','Restaurant','Other'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>category=v??category)),
    const SizedBox(height:12),InputDecorator(decoration:const InputDecoration(labelText:'Detected code type'),child:Text(format)),
    const Divider(height:28),const Text('Optional rewards balance',style:TextStyle(fontWeight:FontWeight.bold)),
    TextField(controller:balanceLabel,decoration:const InputDecoration(labelText:'Balance name',hintText:'Points / Rewards / Cashback')),
    TextField(controller:balance,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Balance amount',hintText:'Leave empty if not tracked')),
    const SizedBox(height:24),FilledButton(onPressed:()=>_save(),child:const Text('Save card'))
  ]));
  void _save(){if(name.text.trim().isEmpty||value.text.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter the card name and barcode/QR value.')));return;}final amount=double.tryParse(balance.text.trim());Navigator.pop(context,LoyaltyCard(id:uuid.v4(),name:name.text.trim(),value:value.text.trim(),format:format,category:category,balance:amount,balanceLabel:balanceLabel.text.trim().isEmpty?'Rewards':balanceLabel.text.trim()));}
}

class ScanScreen extends StatefulWidget{
  const ScanScreen({super.key,required this.onScan});final void Function(String,String) onScan;
  @override State<ScanScreen> createState()=>_ScanScreenState();
}
class _ScanScreenState extends State<ScanScreen>{
  bool handled=false;
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Scan card code')),body:MobileScanner(onDetect:(capture){if(handled||capture.barcodes.isEmpty)return;final b=capture.barcodes.first;final raw=b.rawValue;if(raw==null||raw.isEmpty)return;handled=true;widget.onScan(raw,b.format.name);},errorBuilder:(context,error,child)=>Center(child:Text('Camera error: ${error.errorCode.name}\nPlease allow camera access.'))));
}

class CardDetails extends StatefulWidget{
  const CardDetails({super.key,required this.card,required this.onChanged,required this.onDelete});
  final LoyaltyCard card;final VoidCallback onChanged,onDelete;
  @override State<CardDetails> createState()=>_CardDetailsState();
}
class _CardDetailsState extends State<CardDetails>{
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.card.name),actions:[IconButton(icon:const Icon(Icons.delete_outline),onPressed:widget.onDelete)]),body:ListView(padding:const EdgeInsets.all(20),children:[
    Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xff1a2833),borderRadius:BorderRadius.circular(22)),child:Column(children:[Text(widget.card.name,style:const TextStyle(fontSize:21,fontWeight:FontWeight.bold)),const SizedBox(height:6),Text('${widget.card.category} • ${widget.card.format}',style:const TextStyle(color:Colors.white60)),const SizedBox(height:28),_barcode(widget.card),const SizedBox(height:12),SelectableText(widget.card.value,textAlign:TextAlign.center),const SizedBox(height:8),const Text('Show this code to the cashier',style:TextStyle(color:Colors.white70))])),
    const SizedBox(height:20),Card(child:ListTile(title:Text(widget.card.balance==null?'Add rewards balance':'${widget.card.balanceLabel}: ${widget.card.balance!.toStringAsFixed(2)}'),subtitle:const Text('Balance is manually tracked in this version'),trailing:const Icon(Icons.edit),onTap:_editBalance)),
    const SizedBox(height:8),OutlinedButton.icon(onPressed:()=>_editBalance(),icon:const Icon(Icons.account_balance_wallet),label:const Text('Update rewards balance'))
  ]));
  Widget _barcode(LoyaltyCard c){
    Barcode? b;
    final f=c.format.toLowerCase();
    try{
      if(f.contains('qr'))b=Barcode.qrCode();
      else if(f.contains('code128'))b=Barcode.code128();
      else if(f.contains('code39'))b=Barcode.code39();
      else if(f.contains('ean13'))b=Barcode.ean13();
      else if(f.contains('ean8'))b=Barcode.ean8();
      else if(f.contains('upca')||f.contains('upc_a'))b=Barcode.upcA();
      else if(f.contains('upce')||f.contains('upc_e'))b=Barcode.upcE();
      else if(f.contains('codabar'))b=Barcode.codabar();
      else if(f.contains('itf'))b=Barcode.itf();
      else b=Barcode.qrCode();
      return Container(color:Colors.white,padding:const EdgeInsets.all(12),child:BarcodeWidget(barcode:b,data:c.value,width:320,height:b==Barcode.qrCode()?260:110,drawText:false));
    }catch(_){return Container(color:Colors.white,padding:const EdgeInsets.all(14),child:Text('Code cannot be regenerated for this format. Show the stored value instead:\n${c.value}',style:const TextStyle(color:Colors.black),textAlign:TextAlign.center));}
  }
  Future<void> _editBalance()async{
    final amount=TextEditingController(text:widget.card.balance?.toString()??'');
    final label=TextEditingController(text:widget.card.balanceLabel);
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Update rewards balance'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:label,decoration:const InputDecoration(labelText:'Balance type')),TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))]));
    if(ok==true){widget.card.balance=double.tryParse(amount.text);widget.card.balanceLabel=label.text.trim().isEmpty?'Rewards':label.text.trim();widget.onChanged();setState((){});}
  }
}

class UnlockScreen extends StatefulWidget{
  const UnlockScreen({super.key,required this.onUnlocked});final VoidCallback onUnlocked;
  @override State<UnlockScreen> createState()=>_UnlockScreenState();
}
class _UnlockScreenState extends State<UnlockScreen>{
  final pin=TextEditingController();String error='';bool busy=false;
  @override void initState(){super.initState();_tryBio();}
  Future<void> _tryBio()async{
    try{final auth=LocalAuthentication();if(await auth.canCheckBiometrics||await auth.isDeviceSupported()){final ok=await auth.authenticate(localizedReason:'Unlock your Loyalty Wallet',options:const AuthenticationOptions(biometricOnly:false,stickyAuth:true));if(ok)widget.onUnlocked();}}catch(_){}
  }
  @override Widget build(BuildContext context)=>Scaffold(body:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.lock,size:64),const SizedBox(height:12),const Text('Wallet locked',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const SizedBox(height:14),TextField(controller:pin,obscureText:true,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'PIN',errorText:error.isEmpty?null:error)),const SizedBox(height:12),FilledButton(onPressed:_unlock,child:const Text('Unlock')),TextButton(onPressed:_tryBio,child:const Text('Try fingerprint / device biometrics'))]))));
  Future<void> _unlock()async{
    final salt=await storage.read(key:'pin_salt'),stored=await storage.read(key:'pin_hash');
    if(salt==null||stored==null){widget.onUnlocked();return;}
    final hash=sha256.convert(utf8.encode('$salt:${pin.text}')).toString();
    if(hash==stored)widget.onUnlocked();else setState(()=>error='Incorrect PIN');
  }
}
Future<String?> showPinSetup(BuildContext context)async{
  final c=TextEditingController(),c2=TextEditingController();
  return showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Set a wallet PIN'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:c,obscureText:true,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Choose PIN (4+ digits)')),TextField(controller:c2,obscureText:true,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Confirm PIN'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:(){if(c.text.length<4||c.text!=c2.text){ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content:Text('PINs must match and be at least 4 digits.')));return;}Navigator.pop(ctx,c.text);},child:const Text('Enable protection'))]);
}
