import 'package:flutter/widgets.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

/// Everything the waiter reads, in English and Arabic (waiter-app, WA1).
/// The till's refusals arrive as codes and are worded here, so a handheld set
/// to Arabic never shows the till's English.
sealed class WaiterStrings {
  const WaiterStrings();

  static WaiterStrings of(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar' ? const ArWaiterStrings() : const EnWaiterStrings();

  bool get arabic;

  /// Between a line's modifiers: the comma of the language on screen.
  String get listSeparator => arabic ? '، ' : ', ';
  String get appTitle;
  String get languageToggle;

  // Pairing
  String get connectTitle;
  String get connectIntro;
  String get tillAddress;
  String get tillAddressHint;
  String get pairingCode;
  String get pairingCodeHint;
  String get deviceName;
  String get deviceNameHint;
  String get pairAction;
  String get unpairAction;
  String unpairConfirm(String till);

  // Sign in
  String get pinTitle;
  String pairedWith(String till);
  String get signInAction;
  String get signOutAction;

  // Floor
  String get floorTitle;
  String get tableFree;
  String get tableOpen;
  String get tableBillAsked;
  String items(int n);
  String guests(int n);
  String get noTables;
  String floorSummary({required int open, required int paying, required int free});
  String get noArea;

  // Check
  String get menu;
  String get check;
  String get allItems;
  String get emptyCheck;
  String get sendRound;
  String get sending;
  String sent(int round);
  String get notSentYet;
  String get voided;
  String get subtotal;
  String get service;
  String get tax;
  String get discount;
  String get total;
  String get addToCheck;
  String get quantity;
  String get note;
  String get noteHint;
  String get removeLine;
  String get guestsLabel;
  String get unavailable;
  String get required;
  String chooseUpTo(int n);
  String get roundSent;
  String get checkChangedElsewhere;
  String get notSentHeader;
  String notSentCount(int n);
  String sendRoundCount(int n);
  String checkTab(int n);
  String get openMenu;
  String get searchMenu;
  String get noMatches;
  String get estimate;
  String get retry;
  String get cancel;
  String get save;
  String get refresh;

  /// The till's answer, worded for the waiter.
  String failure(WaiterLinkFailure failure) => switch (failure.code) {
    WaiterError.unpaired => unpaired,
    WaiterError.revoked => revoked,
    WaiterError.badPairingCode => badCode,
    WaiterError.signInRequired => signInAgain,
    WaiterError.wrongPin => wrongPin,
    WaiterError.tooManyAttempts => tooMany,
    WaiterError.notPermitted => notPermitted,
    WaiterError.checkChanged => checkChangedElsewhere,
    WaiterError.refused => refusal(failure.detail),
    WaiterError.versionMismatch => versionMismatch,
    'UNREACHABLE' => unreachable,
    _ => tillProblem,
  };

  String refusal(String? reason) => switch (reason) {
    'out_of_stock' => outOfStock,
    'options_required' => optionsRequired,
    'too_many_options' => tooManyOptions,
    'line_sent' => lineSent,
    'nothing_to_send' => nothingToSend,
    'payment_started' => paymentStarted,
    _ => refusedGeneric,
  };

  String get unpaired;
  String get revoked;
  String get badCode;
  String get signInAgain;
  String get wrongPin;
  String get tooMany;
  String get notPermitted;
  String get versionMismatch;
  String get unreachable;
  String get tillProblem;
  String get outOfStock;
  String get optionsRequired;
  String get tooManyOptions;
  String get lineSent;
  String get nothingToSend;
  String get paymentStarted;
  String get refusedGeneric;
}

class EnWaiterStrings extends WaiterStrings {
  const EnWaiterStrings();

  @override
  bool get arabic => false;
  @override
  String get appTitle => 'XOrder Waiter';
  @override
  String get languageToggle => 'العربية';
  @override
  String get connectTitle => 'Pair with the till';
  @override
  String get connectIntro =>
      'On the main till open Settings › Waiter devices, turn it on and press "Pair a device". '
      'Type the address and the code it shows.';
  @override
  String get tillAddress => 'Till address';
  @override
  String get tillAddressHint => '192.168.1.20:8787';
  @override
  String get pairingCode => 'Pairing code';
  @override
  String get pairingCodeHint => '6 digits';
  @override
  String get deviceName => 'Name for this device';
  @override
  String get deviceNameHint => 'Phone 1';
  @override
  String get pairAction => 'Pair';
  @override
  String get unpairAction => 'Unpair this device';
  @override
  String unpairConfirm(String till) => 'Unpair from $till? You will need a new code from the till.';
  @override
  String get pinTitle => 'Sign in with your PIN';
  @override
  String pairedWith(String till) => 'Paired with $till';
  @override
  String get signInAction => 'Sign in';
  @override
  String get signOutAction => 'Sign out';
  @override
  String get floorTitle => 'Tables';
  @override
  String get tableFree => 'Free';
  @override
  String get tableOpen => 'Open';
  @override
  String get tableBillAsked => 'Paying';
  @override
  String items(int n) => n == 1 ? '1 item' : '$n items';
  @override
  String guests(int n) => n == 1 ? '1 guest' : '$n guests';
  @override
  String get noTables => 'The till has no tables. Add them in the back office.';
  @override
  String floorSummary({required int open, required int paying, required int free}) =>
      '$open open · $paying paying · $free free';
  @override
  String get noArea => 'No area';
  @override
  String get menu => 'Menu';
  @override
  String get check => 'Check';
  @override
  String get allItems => 'All';
  @override
  String get emptyCheck => 'Nothing on this table yet. Tap an item to add it.';
  @override
  String get sendRound => 'Send to kitchen';
  @override
  String get sending => 'Sending…';
  @override
  String sent(int round) => 'Round $round';
  @override
  String get notSentYet => 'Not sent';
  @override
  String get voided => 'Voided';
  @override
  String get subtotal => 'Subtotal';
  @override
  String get service => 'Service';
  @override
  String get tax => 'Tax';
  @override
  String get discount => 'Discount';
  @override
  String get total => 'Total';
  @override
  String get addToCheck => 'Add';
  @override
  String get quantity => 'Quantity';
  @override
  String get note => 'Note';
  @override
  String get noteHint => 'No onions, well done…';
  @override
  String get removeLine => 'Remove';
  @override
  String get guestsLabel => 'Guests';
  @override
  String get unavailable => 'Unavailable';
  @override
  String get required => 'Required';
  @override
  String chooseUpTo(int n) => 'Choose up to $n';
  @override
  String get roundSent => 'Sent to the kitchen.';
  @override
  String get checkChangedElsewhere =>
      'This table was changed on another device. You are now seeing the latest check; please redo your last change.';
  @override
  String get notSentHeader => 'Not sent yet';
  @override
  String notSentCount(int n) => n == 1 ? '1 line not sent' : '$n lines not sent';
  @override
  String sendRoundCount(int n) => 'Send to kitchen ($n)';
  @override
  String checkTab(int n) => 'Check ($n)';
  @override
  String get openMenu => 'Open the menu';
  @override
  String get searchMenu => 'Search the menu';
  @override
  String get noMatches => 'Nothing matches.';
  @override
  String get estimate => '≈';
  @override
  String get retry => 'Try again';
  @override
  String get cancel => 'Cancel';
  @override
  String get save => 'Save';
  @override
  String get refresh => 'Refresh';
  @override
  String get unpaired => 'This device is not paired with the till.';
  @override
  String get revoked => 'This device was removed on the till. Pair it again.';
  @override
  String get badCode => 'That code is wrong or expired. Ask for a new one on the till.';
  @override
  String get signInAgain => 'Please sign in again.';
  @override
  String get wrongPin => 'Wrong PIN.';
  @override
  String get tooMany => 'Too many tries. Wait a minute and try again.';
  @override
  String get notPermitted => 'You are not allowed to do that. Ask a manager.';
  @override
  String get versionMismatch => 'This app and the till are different versions. Update the older one.';
  @override
  String get unreachable => 'Cannot reach the till. Check the Wi-Fi and that the till is on.';
  @override
  String get tillProblem => 'The till could not do that. Try again.';
  @override
  String get outOfStock => 'That item is not available.';
  @override
  String get optionsRequired => 'Choose the required options first.';
  @override
  String get tooManyOptions => 'Too many options chosen.';
  @override
  String get lineSent => 'That line was already sent. Ask the cashier to void it.';
  @override
  String get nothingToSend => 'Nothing new to send.';
  @override
  String get paymentStarted => 'The cashier is taking payment for this table.';
  @override
  String get refusedGeneric => 'The till refused that change.';
}

class ArWaiterStrings extends WaiterStrings {
  const ArWaiterStrings();

  @override
  bool get arabic => true;
  @override
  String get appTitle => 'XOrder ويتر';
  @override
  String get languageToggle => 'English';
  @override
  String get connectTitle => 'الإقران بجهاز الكاشير';
  @override
  String get connectIntro =>
      'على الجهاز الرئيسي افتح الإعدادات › أجهزة الويتر، شغّلها واضغط "إقران جهاز". '
      'اكتب العنوان والرمز الظاهرين.';
  @override
  String get tillAddress => 'عنوان الجهاز';
  @override
  String get tillAddressHint => '192.168.1.20:8787';
  @override
  String get pairingCode => 'رمز الإقران';
  @override
  String get pairingCodeHint => '6 أرقام';
  @override
  String get deviceName => 'اسم هذا الجهاز';
  @override
  String get deviceNameHint => 'هاتف 1';
  @override
  String get pairAction => 'إقران';
  @override
  String get unpairAction => 'إلغاء إقران هذا الجهاز';
  @override
  String unpairConfirm(String till) => 'إلغاء الإقران مع $till؟ ستحتاج رمزًا جديدًا من الجهاز.';
  @override
  String get pinTitle => 'سجّل الدخول برقمك السري';
  @override
  String pairedWith(String till) => 'مقترن بـ $till';
  @override
  String get signInAction => 'دخول';
  @override
  String get signOutAction => 'خروج';
  @override
  String get floorTitle => 'الطاولات';
  @override
  String get tableFree => 'متاحة';
  @override
  String get tableOpen => 'مفتوحة';
  @override
  String get tableBillAsked => 'جارٍ الدفع';
  @override
  String items(int n) => n == 1 ? 'صنف واحد' : '$n أصناف';
  @override
  String guests(int n) => n == 1 ? 'ضيف واحد' : '$n ضيوف';
  @override
  String get noTables => 'لا توجد طاولات على الجهاز. أضفها من الإدارة.';
  @override
  String floorSummary({required int open, required int paying, required int free}) =>
      '$open مفتوحة · $paying تدفع · $free متاحة';
  @override
  String get noArea => 'بدون منطقة';
  @override
  String get menu => 'المنيو';
  @override
  String get check => 'الحساب';
  @override
  String get allItems => 'الكل';
  @override
  String get emptyCheck => 'لا شيء على هذه الطاولة بعد. اضغط على صنف لإضافته.';
  @override
  String get sendRound => 'إرسال للمطبخ';
  @override
  String get sending => 'جارٍ الإرسال…';
  @override
  String sent(int round) => 'الدفعة $round';
  @override
  String get notSentYet => 'لم يُرسل';
  @override
  String get voided => 'ملغى';
  @override
  String get subtotal => 'المجموع الفرعي';
  @override
  String get service => 'الخدمة';
  @override
  String get tax => 'الضريبة';
  @override
  String get discount => 'الخصم';
  @override
  String get total => 'الإجمالي';
  @override
  String get addToCheck => 'إضافة';
  @override
  String get quantity => 'الكمية';
  @override
  String get note => 'ملاحظة';
  @override
  String get noteHint => 'بدون بصل، مستوية جيدًا…';
  @override
  String get removeLine => 'حذف';
  @override
  String get guestsLabel => 'الضيوف';
  @override
  String get unavailable => 'غير متاح';
  @override
  String get required => 'إجباري';
  @override
  String chooseUpTo(int n) => 'اختر حتى $n';
  @override
  String get roundSent => 'أُرسل للمطبخ.';
  @override
  String get checkChangedElsewhere =>
      'تغيّرت هذه الطاولة على جهاز آخر. يظهر لك الآن آخر حساب؛ أعد آخر تعديل من فضلك.';
  @override
  String get notSentHeader => 'بانتظار الإرسال';
  @override
  String notSentCount(int n) => n == 1 ? 'صنف واحد لم يُرسل' : '$n أصناف لم تُرسل';
  @override
  String sendRoundCount(int n) => 'إرسال للمطبخ ($n)';
  @override
  String checkTab(int n) => 'الحساب ($n)';
  @override
  String get openMenu => 'افتح المنيو';
  @override
  String get searchMenu => 'ابحث في المنيو';
  @override
  String get noMatches => 'لا نتائج.';
  @override
  String get estimate => '≈';
  @override
  String get retry => 'حاول مرة أخرى';
  @override
  String get cancel => 'إلغاء';
  @override
  String get save => 'حفظ';
  @override
  String get refresh => 'تحديث';
  @override
  String get unpaired => 'هذا الجهاز غير مقترن بجهاز الكاشير.';
  @override
  String get revoked => 'أُلغي هذا الجهاز من جهاز الكاشير. اقرنه من جديد.';
  @override
  String get badCode => 'الرمز خطأ أو منتهٍ. اطلب رمزًا جديدًا من الجهاز.';
  @override
  String get signInAgain => 'سجّل الدخول من جديد من فضلك.';
  @override
  String get wrongPin => 'الرقم السري خطأ.';
  @override
  String get tooMany => 'محاولات كثيرة. انتظر دقيقة وحاول مرة أخرى.';
  @override
  String get notPermitted => 'غير مسموح لك بذلك. اطلب من المدير.';
  @override
  String get versionMismatch => 'هذا التطبيق وجهاز الكاشير بإصدارين مختلفين. حدّث الأقدم.';
  @override
  String get unreachable => 'تعذّر الوصول لجهاز الكاشير. تأكد من الواي فاي ومن تشغيل الجهاز.';
  @override
  String get tillProblem => 'تعذّر على الجهاز تنفيذ ذلك. حاول مرة أخرى.';
  @override
  String get outOfStock => 'هذا الصنف غير متاح.';
  @override
  String get optionsRequired => 'اختر الخيارات الإجبارية أولًا.';
  @override
  String get tooManyOptions => 'خيارات أكثر من المسموح.';
  @override
  String get lineSent => 'هذا الصنف أُرسل بالفعل. اطلب من الكاشير إلغاءه.';
  @override
  String get nothingToSend => 'لا يوجد جديد للإرسال.';
  @override
  String get paymentStarted => 'الكاشير يحصّل حساب هذه الطاولة.';
  @override
  String get refusedGeneric => 'رفض الجهاز هذا التعديل.';
}
