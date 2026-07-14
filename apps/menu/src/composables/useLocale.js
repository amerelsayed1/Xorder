import { ref, computed, watch } from 'vue'

const translations = {
    ar: {
        home: 'الرئيسية', offers: 'العروض', branches: 'الفروع', cart: 'السلة',
        cart_empty: 'اختر أصنافك من القائمة وسنجهّزها في رسالة طلب جاهزة لإرسالها عبر واتساب',
        cart_empty_title: 'سلتك فارغة',
        required: 'مطلوب', choose: 'اختر', open: 'مفتوح', closed: 'مغلق', add: 'إضافة',
        from: 'يبدأ من', location: 'الموقع', total: 'الإجمالي', order_wa: 'اطلب عبر واتساب',
        remove: 'حذف', unavailable: 'القائمة غير متاحة حالياً', view_cart: 'عرض السلة',
        new_order: 'طلب جديد', qty: 'الكمية', your_details: 'بيانات الطلب',
        f_name: 'الاسم', f_phone: 'رقم الهاتف', f_email: 'البريد الإلكتروني', f_address: 'العنوان', f_note: 'ملاحظات',
        f_name_ph: 'اكتب اسمك', f_phone_ph: '01xxxxxxxxx', f_note_ph: 'أي ملاحظات إضافية',
        optional: 'اختياري', item: 'صنف', items: 'أصناف',
        sending: 'جاري الإرسال…', cancel: 'إلغاء', close: 'إغلاق', no_items: 'لا توجد أصناف هنا بعد',
        order_sent: 'تم تجهيز طلبك في واتساب', order_sent_hint: 'أكمل إرسال الرسالة من تطبيق واتساب. لم يُفتح واتساب؟',
        reopen_wa: 'فتح واتساب مرة أخرى', error_generic: 'حدث خطأ ما. حاول مرة أخرى.',
        order_ref: 'رقم الطلب', powered_by: 'يعمل بواسطة',
        order_type: 'نوع الطلب', order_type_select: 'حدد نوع الطلب',
        delivery: 'توصيل', pickup: 'استلام', dine_in: 'تناول بالمطعم',
        add_from_menu: 'أضف أصنافك من القائمة', contact: 'تواصل معنا', whatsapp: 'واتساب',
        contact_wa: 'تواصل عبر واتساب',
        price_by_choice: 'السعر حسب الاختيار',
        all: 'الكل', search_menu: 'ابحث في المنيو',
        todays_picks: 'مختاراتنا اليوم', menu_of: 'منيو', item_count: 'صنف', items_count: 'أصناف',
        popular: 'الأكثر طلبًا', item_unavailable: 'غير متاح حاليًا',
        no_results_title: 'لا توجد نتائج', no_results_hint: 'جرّب كلمة بحث أخرى أو تصنيفًا مختلفًا',
        info: 'معلومات', share: 'مشاركة', link_copied: 'تم نسخ الرابط',
        review_cart: 'مراجعة السلة', order_details: 'بيانات الطلب', checkout_title: 'إتمام الطلب',
        clear_cart: 'تفريغ السلة', edit_cart: 'تعديل السلة',
        continue_checkout: 'متابعة لإتمام الطلب', review_hint: 'راجع طلبك قبل إدخال بيانات الاستلام',
        data_safe: 'كل البيانات آمنة', wa_note: 'سيتم تجهيز تفاصيل طلبك في رسالة واتساب قبل الإرسال',
        back_to_cart: 'الرجوع إلى السلة',
        choose_options: 'اختر إضافاتك', free: 'مجانًا', item_note: 'ملاحظات على الصنف',
        item_note_ph: 'مثال: بدون بصل', add_to_cart: 'إضافة إلى السلة',
        my_info: 'بياناتي', note_label: 'ملاحظة',
    },
    en: {
        home: 'Home', offers: 'Offers', branches: 'Branches', cart: 'Cart',
        cart_empty: 'Pick your items and we\'ll turn them into a ready order message to send on WhatsApp',
        cart_empty_title: 'Your cart is empty',
        required: 'Required', choose: 'Choose', open: 'Open', closed: 'Closed', add: 'Add',
        from: 'From', location: 'Location', total: 'Total', order_wa: 'Order via WhatsApp',
        remove: 'Remove', unavailable: 'The menu is currently unavailable', view_cart: 'View cart',
        new_order: 'New order', qty: 'Qty', your_details: 'Order details',
        f_name: 'Name', f_phone: 'Phone number', f_email: 'Email', f_address: 'Address', f_note: 'Notes',
        f_name_ph: 'Your name', f_phone_ph: '01xxxxxxxxx', f_note_ph: 'Any extra notes',
        optional: 'Optional', item: 'item', items: 'items',
        sending: 'Sending…', cancel: 'Cancel', close: 'Close', no_items: 'No items here yet',
        order_sent: 'Your order is ready in WhatsApp', order_sent_hint: 'Finish sending the message in WhatsApp. Didn\'t open?',
        reopen_wa: 'Open WhatsApp again', error_generic: 'Something went wrong. Please try again.',
        order_ref: 'Order no.', powered_by: 'Powered by',
        order_type: 'Order type', order_type_select: 'Select order type',
        delivery: 'Delivery', pickup: 'Pickup', dine_in: 'Dine-in',
        add_from_menu: 'Add items from the menu', contact: 'Contact us', whatsapp: 'WhatsApp',
        contact_wa: 'Chat on WhatsApp',
        price_by_choice: 'Price by selection',
        all: 'All', search_menu: 'Search the menu',
        todays_picks: "Today's picks", menu_of: 'Menu of', item_count: 'item', items_count: 'items',
        popular: 'Most popular', item_unavailable: 'Currently unavailable',
        no_results_title: 'No results', no_results_hint: 'Try another search term or category',
        info: 'Info', share: 'Share', link_copied: 'Link copied',
        review_cart: 'Review cart', order_details: 'Order details', checkout_title: 'Checkout',
        clear_cart: 'Clear cart', edit_cart: 'Edit cart',
        continue_checkout: 'Continue to checkout', review_hint: 'Review your order before entering your details',
        data_safe: 'Your data is safe', wa_note: 'Your order details will be prepared in a WhatsApp message before sending',
        back_to_cart: 'Back to cart',
        choose_options: 'Choose your extras', free: 'Free', item_note: 'Item notes',
        item_note_ph: 'e.g. no onions', add_to_cart: 'Add to cart',
        my_info: 'My info', note_label: 'Note',
    },
}

export function useLocale(defaultLang = 'ar') {
    const locale = ref(defaultLang)
    const isAr = computed(() => locale.value === 'ar')

    const t = (key) => translations[locale.value][key] || key

    function syncDir() {
        document.documentElement.lang = locale.value
        document.documentElement.dir = isAr.value ? 'rtl' : 'ltr'
    }

    function localize(obj, field = 'name') {
        if (!obj) return ''
        return obj[`${field}_${locale.value}`] || obj[`${field}_en`] || obj[`${field}_ar`] || ''
    }

    watch(locale, syncDir, { immediate: true })

    return {
        locale,
        isAr,
        t,
        localize,
    }
}
