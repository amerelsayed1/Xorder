import { createI18n } from 'vue-i18n'

const messages = {
    en: {
        app: { title: 'QR Menu' },
        nav: {
            dashboard: 'Dashboard', restaurants: 'Restaurants', profile: 'Profile',
            categories: 'Categories', items: 'Menu Items', qr: 'QR Code', logout: 'Logout',
        },
        auth: {
            login: 'Log in', email: 'Email', password: 'Password', remember: 'Remember me',
            signing_in: 'Signing in…', welcome: 'Sign in to your account',
        },
        common: {
            save: 'Save', cancel: 'Cancel', create: 'Create', edit: 'Edit', delete: 'Delete',
            actions: 'Actions', status: 'Status', search: 'Search', loading: 'Loading…',
            none: 'Nothing here yet.', confirm_delete: 'Are you sure you want to delete this?',
            active: 'Active', inactive: 'Inactive', yes: 'Yes', no: 'No', back: 'Back',
            name_ar: 'Name (Arabic)', name_en: 'Name (English)',
            description_ar: 'Description (Arabic)', description_en: 'Description (English)',
            available: 'Available', unavailable: 'Unavailable', featured: 'Featured',
        },
        restaurant: {
            create: 'Create Restaurant', name: 'Restaurant name', slug: 'Slug',
            slug_warning: 'Changing the slug breaks any QR codes already printed with the old URL.',
            admin_name: 'Admin name', admin_email: 'Admin email', admin_password: 'Admin password',
            password_hint: 'Leave blank to auto-generate a secure password.',
            phone: 'Phone', whatsapp: 'WhatsApp number', address: 'Address',
            brand_color: 'Brand color', secondary_color: 'Secondary color',
            language: 'Default language', subscription: 'Subscription', plan: 'Plan',
            public_url: 'Public URL', generated_password: 'Generated password',
            generated_password_note: 'Copy this now — it will not be shown again.',
        },
        stats: {
            total_categories: 'Categories', total_items: 'Menu items',
            available_items: 'Available', unavailable_items: 'Unavailable',
            quick_actions: 'Quick actions',
        },
        item: { price: 'Price', discounted_price: 'Discounted price', category: 'Category' },
    },
    ar: {
        app: { title: 'قائمة QR' },
        nav: {
            dashboard: 'لوحة التحكم', restaurants: 'المطاعم', profile: 'الملف الشخصي',
            categories: 'الأقسام', items: 'الأصناف', qr: 'رمز QR', logout: 'تسجيل الخروج',
        },
        auth: {
            login: 'تسجيل الدخول', email: 'البريد الإلكتروني', password: 'كلمة المرور',
            remember: 'تذكرني', signing_in: 'جارٍ تسجيل الدخول…', welcome: 'سجّل الدخول إلى حسابك',
        },
        common: {
            save: 'حفظ', cancel: 'إلغاء', create: 'إنشاء', edit: 'تعديل', delete: 'حذف',
            actions: 'إجراءات', status: 'الحالة', search: 'بحث', loading: 'جارٍ التحميل…',
            none: 'لا يوجد شيء بعد.', confirm_delete: 'هل أنت متأكد من الحذف؟',
            active: 'نشط', inactive: 'غير نشط', yes: 'نعم', no: 'لا', back: 'رجوع',
            name_ar: 'الاسم (عربي)', name_en: 'الاسم (إنجليزي)',
            description_ar: 'الوصف (عربي)', description_en: 'الوصف (إنجليزي)',
            available: 'متاح', unavailable: 'غير متاح', featured: 'مميز',
        },
        restaurant: {
            create: 'إنشاء مطعم', name: 'اسم المطعم', slug: 'المعرّف',
            slug_warning: 'تغيير المعرّف سيُبطل رموز QR المطبوعة بالرابط القديم.',
            admin_name: 'اسم المسؤول', admin_email: 'بريد المسؤول', admin_password: 'كلمة مرور المسؤول',
            password_hint: 'اتركها فارغة لإنشاء كلمة مرور آمنة تلقائياً.',
            phone: 'الهاتف', whatsapp: 'رقم واتساب', address: 'العنوان',
            brand_color: 'لون العلامة', secondary_color: 'اللون الثانوي',
            language: 'اللغة الافتراضية', subscription: 'الاشتراك', plan: 'الخطة',
            public_url: 'الرابط العام', generated_password: 'كلمة المرور المُنشأة',
            generated_password_note: 'انسخها الآن — لن تظهر مرة أخرى.',
        },
        stats: {
            total_categories: 'الأقسام', total_items: 'الأصناف',
            available_items: 'متاح', unavailable_items: 'غير متاح',
            quick_actions: 'إجراءات سريعة',
        },
        item: { price: 'السعر', discounted_price: 'السعر بعد الخصم', category: 'القسم' },
    },
}

export const i18n = createI18n({
    legacy: false,
    locale: localStorage.getItem('locale') || 'en',
    fallbackLocale: 'en',
    messages,
})

export function setLocale(locale) {
    i18n.global.locale.value = locale
    localStorage.setItem('locale', locale)
    document.documentElement.lang = locale
    document.documentElement.dir = locale === 'ar' ? 'rtl' : 'ltr'
}
