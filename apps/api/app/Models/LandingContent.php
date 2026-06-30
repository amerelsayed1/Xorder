<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class LandingContent extends Model
{
    protected $fillable = ['content'];

    protected $casts = [
        'content' => 'array',
    ];

    /**
     * The landing page is a singleton. Return the one row, creating it from the
     * baked defaults on first access so the public site always has content.
     *
     * Stored content is layered over the current defaults so that rows saved
     * before a new section existed still resolve every key (fallback content).
     */
    public static function current(): self
    {
        $row = static::firstOrCreate([], ['content' => static::defaultContent()]);
        $row->content = static::fillDefaults(static::defaultContent(), $row->content ?? []);

        return $row;
    }

    /**
     * Recursively fill keys missing from $stored using $defaults. Associative
     * maps are merged key-by-key; sequential lists (repeaters like packages or
     * industries) are taken wholesale from $stored when present, so the admin
     * stays in control of how many items appear.
     */
    private static function fillDefaults(mixed $defaults, mixed $stored): mixed
    {
        if (! is_array($defaults)) {
            return $stored ?? $defaults;
        }
        if (! is_array($stored)) {
            return $defaults;
        }
        // Repeater (list): the admin's array wins entirely.
        if (array_is_list($defaults)) {
            return $stored;
        }

        $out = $defaults;
        foreach ($defaults as $key => $value) {
            $out[$key] = array_key_exists($key, $stored)
                ? static::fillDefaults($value, $stored[$key])
                : $value;
        }
        // Preserve any extra keys the admin saved that defaults don't know about.
        foreach ($stored as $key => $value) {
            if (! array_key_exists($key, $out)) {
                $out[$key] = $value;
            }
        }

        return $out;
    }

    /**
     * A bilingual value: ['en' => ..., 'ar' => ...].
     */
    private static function bi(string $en, string $ar): array
    {
        return ['en' => $en, 'ar' => $ar];
    }

    /**
     * Default content for the sales-focused landing page. A super admin can
     * override every field; this is the fallback the public site renders until
     * then.
     */
    public static function defaultContent(): array
    {
        $bi = fn (string $en, string $ar) => static::bi($en, $ar);

        return [
            'hero' => [
                'badge' => $bi('QR menu & direct ordering — no commission', 'قائمة QR وطلب مباشر — بدون عمولة'),
                'title' => $bi(
                    'QR Menu & Direct Ordering System for Restaurants — No Commission',
                    'نظام قائمة QR والطلب المباشر للمطاعم — بدون عمولة'
                ),
                'sub' => $bi(
                    'Create a professional digital menu for your restaurant, let customers order directly from their phones, and manage orders easily without paying commission on every order.',
                    'أنشئ قائمة رقمية احترافية لمطعمك، ودع العملاء يطلبون مباشرة من هواتفهم، وأدر الطلبات بسهولة دون دفع عمولة على كل طلب.'
                ),
                'cta' => $bi('Request a Demo', 'اطلب عرضاً توضيحياً'),
                'primary_link' => '#lead',
                'secondary' => $bi('View Live Menu Demo', 'شاهد قائمة حية'),
                'secondary_link' => '',
                'no_commission_label' => $bi('0% commission per order', '٠٪ عمولة على كل طلب'),
                'ready_label' => $bi('Ready in 48 hours', 'جاهز خلال ٤٨ ساعة'),
                'whatsapp_label' => $bi('Chat on WhatsApp', 'تواصل عبر واتساب'),
            ],

            'proof' => [
                ['title' => $bi('0%', '٠٪'), 'text' => $bi('Commission per order', 'عمولة على كل طلب')],
                ['title' => $bi('48h', '٤٨ ساعة'), 'text' => $bi('Ready to launch', 'جاهز للإطلاق')],
                ['title' => $bi('No app', 'بدون تطبيق'), 'text' => $bi('Guests just scan', 'يكفي أن يمسح الضيوف')],
            ],

            'offer' => [
                'title' => $bi('Start with a QR Menu for Your Restaurant', 'ابدأ بقائمة QR لمطعمك'),
                'text' => $bi(
                    'Launch a professional QR menu for your restaurant or cafe, update items and prices anytime, and give your customers a smooth mobile ordering experience.',
                    'أطلق قائمة QR احترافية لمطعمك أو مقهاك، وحدّث الأصناف والأسعار في أي وقت، وامنح عملاءك تجربة طلب سلسة من الهاتف.'
                ),
                'items' => [
                    ['icon' => '▦', 'text' => $bi('Digital QR menu', 'قائمة QR رقمية')],
                    ['icon' => '✎', 'text' => $bi('Easy menu updates', 'تحديث سهل للقائمة')],
                    ['icon' => '✦', 'text' => $bi('Product photos and prices', 'صور المنتجات والأسعار')],
                    ['icon' => '☰', 'text' => $bi('Categories and item details', 'الأقسام وتفاصيل الأصناف')],
                    ['icon' => '⚡', 'text' => $bi('Direct ordering', 'طلب مباشر')],
                    ['icon' => '✆', 'text' => $bi('WhatsApp or dashboard order receiving', 'استقبال الطلبات عبر واتساب أو لوحة التحكم')],
                    ['icon' => '％', 'text' => $bi('No commission per order', 'بدون عمولة على الطلب')],
                ],
            ],

            'problem' => [
                'title' => $bi('Sound familiar?', 'هل يبدو هذا مألوفاً؟'),
                'sub' => $bi('The everyday headaches of running a menu the old way.', 'متاعب يومية لإدارة القائمة بالطريقة القديمة.'),
                'problems' => [
                    ['text' => $bi('Still sending menu images or PDFs on WhatsApp', 'لا تزال ترسل صور القائمة أو ملفات PDF على واتساب')],
                    ['text' => $bi('Printing new menus every time prices change', 'تطبع قوائم جديدة كلما تغيّرت الأسعار')],
                    ['text' => $bi('Receiving messy manual orders', 'تستقبل طلبات يدوية غير منظمة')],
                    ['text' => $bi('Paying high commissions to ordering platforms', 'تدفع عمولات مرتفعة لمنصّات الطلب')],
                    ['text' => $bi('Losing the direct customer relationship', 'تفقد العلاقة المباشرة مع العميل')],
                ],
                'solution_title' => $bi('A channel you control', 'قناة تتحكم بها أنت'),
                'solution_text' => $bi(
                    'Xorder gives restaurants a professional digital menu and direct ordering channel that they fully control.',
                    'يمنح Xorder المطاعم قائمة رقمية احترافية وقناة طلب مباشر يتحكمون بها بالكامل.'
                ),
            ],

            'no_commission' => [
                'title' => $bi('Keep More of Every Order', 'احتفظ بالمزيد من كل طلب'),
                'text' => $bi(
                    'With Xorder, your customers order directly from your restaurant. You pay a predictable subscription instead of losing a percentage from every order.',
                    'مع Xorder يطلب عملاؤك مباشرة من مطعمك. تدفع اشتراكاً ثابتاً بدلاً من خسارة نسبة من كل طلب.'
                ),
                'third_party_title' => $bi('Third-party platforms', 'منصّات الطرف الثالث'),
                'third_party' => [
                    ['text' => $bi('Commission on every order', 'عمولة على كل طلب')],
                    ['text' => $bi('Less control over customers', 'تحكم أقل في العملاء')],
                    ['text' => $bi('Higher long-term cost', 'تكلفة أعلى على المدى الطويل')],
                ],
                'xorder_title' => $bi('Xorder', 'Xorder'),
                'xorder' => [
                    ['text' => $bi('No commission', 'بدون عمولة')],
                    ['text' => $bi('Direct customer orders', 'طلبات مباشرة من العملاء')],
                    ['text' => $bi('Full menu control', 'تحكم كامل في القائمة')],
                    ['text' => $bi('Own branded ordering experience', 'تجربة طلب بهويتك الخاصة')],
                ],
            ],

            'features' => [
                'title' => $bi('Everything you need to sell directly', 'كل ما تحتاجه للبيع مباشرة'),
                'sub' => $bi('Built for restaurants, cafés, and cloud kitchens across the region.', 'مصمم للمطاعم والمقاهي والمطابخ السحابية في المنطقة.'),
                'items' => [
                    ['icon' => '▦', 'title' => $bi('One QR, forever', 'رمز واحد للأبد'), 'text' => $bi('Print it once. Your menu updates instantly — the code never changes.', 'اطبعه مرة واحدة. تتحدث قائمتك فوراً والرمز لا يتغير أبداً.')],
                    ['icon' => '⇆', 'title' => $bi('Bilingual by default', 'ثنائي اللغة افتراضياً'), 'text' => $bi('Arabic and English side by side, with full right-to-left support.', 'العربية والإنجليزية جنباً إلى جنب مع دعم كامل للكتابة من اليمين لليسار.')],
                    ['icon' => '⚡', 'title' => $bi('Live updates', 'تحديثات لحظية'), 'text' => $bi('Mark items sold out or change prices and customers see it immediately.', 'حدّد الأصناف كمنتهية أو غيّر الأسعار ليراها العملاء فوراً.')],
                    ['icon' => '✦', 'title' => $bi('Your brand', 'هويتك'), 'text' => $bi('Custom colors and logo so the menu feels like part of your restaurant.', 'ألوان وشعار مخصص لتبدو القائمة جزءاً من مطعمك.')],
                    ['icon' => '☰', 'title' => $bi('Categories & featured', 'أقسام وأصناف مميزة'), 'text' => $bi('Organize dishes into sections and highlight your best sellers.', 'نظّم الأطباق في أقسام وسلّط الضوء على الأكثر مبيعاً.')],
                    ['icon' => '◍', 'title' => $bi('Simple dashboard', 'لوحة تحكم بسيطة'), 'text' => $bi('Manage everything from one clean panel — no technical skills needed.', 'أدر كل شيء من لوحة واحدة أنيقة — بدون مهارات تقنية.')],
                ],
            ],

            'demo' => [
                'enabled' => true,
                'title' => $bi('Try the Customer Experience', 'جرّب تجربة العميل'),
                'text' => $bi(
                    'Scan the QR code or open the live demo to see how your customers will browse the menu and place an order.',
                    'امسح رمز QR أو افتح العرض الحي لترى كيف سيتصفح عملاؤك القائمة ويقدمون طلباً.'
                ),
                'button' => $bi('Open live demo', 'افتح العرض الحي'),
                'restaurant_slug' => 'xorderrest',
            ],

            'steps' => [
                'title' => $bi('How ordering works', 'كيف يتم الطلب'),
                'items' => [
                    ['title' => $bi('Customer scans QR', 'العميل يمسح رمز QR'), 'text' => $bi('Guests open your live menu on their phone — no app to install.', 'يفتح الضيوف قائمتك الحية على هواتفهم — بدون تطبيق.')],
                    ['title' => $bi('Customer selects items', 'العميل يختار الأصناف'), 'text' => $bi('They browse categories, add items to the cart and confirm.', 'يتصفحون الأقسام ويضيفون الأصناف إلى السلة ويؤكدون.')],
                    ['title' => $bi('Restaurant receives the order', 'المطعم يستقبل الطلب'), 'text' => $bi('The order arrives on WhatsApp or your dashboard, ready to prepare.', 'يصل الطلب عبر واتساب أو لوحة التحكم، جاهزاً للتحضير.')],
                ],
            ],

            'pricing' => [
                'title' => $bi('Packages that grow with you', 'باقات تنمو معك'),
                'sub' => $bi('Start with a menu, add ordering when you are ready.', 'ابدأ بقائمة، وأضف الطلب عندما تكون جاهزاً.'),
                'popular_label' => $bi('Recommended', 'موصى به'),
                'choose_label' => $bi('Request a Demo', 'اطلب عرضاً'),
                'plans' => [
                    [
                        'name' => $bi('Menu Starter', 'باقة القائمة'),
                        'subtitle' => $bi('Best for small cafes and restaurants that need a professional QR menu.', 'الأنسب للمقاهي والمطاعم الصغيرة التي تحتاج قائمة QR احترافية.'),
                        'price_label' => $bi('Contact Sales', 'تواصل مع المبيعات'),
                        'recommended' => false,
                        'enabled' => true,
                        'features' => [
                            $bi('QR menu', 'قائمة QR'),
                            $bi('Menu categories', 'أقسام القائمة'),
                            $bi('Product images', 'صور المنتجات'),
                            $bi('Price updates', 'تحديث الأسعار'),
                            $bi('Restaurant info page', 'صفحة معلومات المطعم'),
                            $bi('QR code ready for printing', 'رمز QR جاهز للطباعة'),
                        ],
                    ],
                    [
                        'name' => $bi('Menu Plus', 'باقة القائمة بلس'),
                        'subtitle' => $bi('Best for restaurants that want customers to order directly.', 'الأنسب للمطاعم التي تريد أن يطلب العملاء مباشرة.'),
                        'price_label' => $bi('Starts from', 'يبدأ من'),
                        'recommended' => true,
                        'enabled' => true,
                        'features' => [
                            $bi('Everything in Menu Starter', 'كل ما في باقة القائمة'),
                            $bi('Cart', 'سلة المشتريات'),
                            $bi('Direct ordering', 'الطلب المباشر'),
                            $bi('WhatsApp or dashboard order receiving', 'استقبال الطلبات عبر واتساب أو لوحة التحكم'),
                            $bi('Offers / coupons', 'العروض والكوبونات'),
                            $bi('Basic order tracking', 'تتبع أساسي للطلبات'),
                        ],
                    ],
                    [
                        'name' => $bi('Restaurant Pro', 'باقة المطعم برو'),
                        'subtitle' => $bi('Best for restaurants with delivery, pickup, or multiple branches.', 'الأنسب للمطاعم ذات التوصيل أو الاستلام أو الفروع المتعددة.'),
                        'price_label' => $bi('Contact Sales', 'تواصل مع المبيعات'),
                        'recommended' => false,
                        'enabled' => true,
                        'features' => [
                            $bi('Everything in Menu Plus', 'كل ما في باقة القائمة بلس'),
                            $bi('Order management dashboard', 'لوحة إدارة الطلبات'),
                            $bi('Pickup and delivery orders', 'طلبات الاستلام والتوصيل'),
                            $bi('Table ordering', 'الطلب من الطاولة'),
                            $bi('Reports', 'التقارير'),
                            $bi('Branch support', 'دعم الفروع'),
                            $bi('Driver app', 'تطبيق السائق'),
                        ],
                    ],
                ],
            ],

            'industries' => [
                'title' => $bi('Made for your kind of place', 'مصمم لنوع مكانك'),
                'sub' => $bi('Xorder fits any food business that takes orders.', 'يناسب Xorder أي نشاط طعام يستقبل الطلبات.'),
                'items' => [
                    ['icon' => '🍽️', 'text' => $bi('Restaurants', 'المطاعم')],
                    ['icon' => '☕', 'text' => $bi('Cafes', 'المقاهي')],
                    ['icon' => '🧁', 'text' => $bi('Dessert shops', 'محلات الحلويات')],
                    ['icon' => '🍱', 'text' => $bi('Cloud kitchens', 'المطابخ السحابية')],
                    ['icon' => '🚚', 'text' => $bi('Food trucks', 'عربات الطعام')],
                    ['icon' => '🥡', 'text' => $bi('Takeaway restaurants', 'مطاعم الوجبات السريعة')],
                    ['icon' => '🏷️', 'text' => $bi('Local food brands', 'العلامات الغذائية المحلية')],
                ],
            ],

            'lead_form' => [
                'title' => $bi('Request My Demo', 'اطلب عرضي التوضيحي'),
                'sub' => $bi('Tell us about your restaurant and we’ll set up a personalised demo.', 'أخبرنا عن مطعمك وسنجهّز لك عرضاً مخصصاً.'),
                'button' => $bi('Request My Demo', 'اطلب عرضي التوضيحي'),
                'success' => $bi('Thanks! We received your request and will be in touch shortly.', 'شكراً لك! استلمنا طلبك وسنتواصل معك قريباً.'),
            ],

            'cta' => [
                'title' => $bi('Ready to launch your menu?', 'جاهز لإطلاق قائمتك؟'),
                'sub' => $bi('Tell us about your restaurant and we’ll set up your digital menu.', 'أخبرنا عن مطعمك وسنجهّز قائمتك الرقمية.'),
                'button' => $bi('Request a Demo', 'اطلب عرضاً توضيحياً'),
                'whatsapp_label' => $bi('WhatsApp', 'واتساب'),
            ],

            'whatsapp' => [
                'number' => '',
                'default_message' => $bi(
                    'Hi Xorder, I’d like a demo for my restaurant.',
                    'مرحباً Xorder، أريد عرضاً توضيحياً لمطعمي.'
                ),
                'floating_enabled' => true,
                'hero_enabled' => true,
            ],

            'seo' => [
                'title' => 'Xorder — QR Menu & Direct Ordering for Restaurants (No Commission)',
                'description' => 'Create a professional QR menu, take direct orders from customers, and manage orders without paying commission on every order. Ready in 48 hours.',
                'og_title' => 'Xorder — QR Menu & Direct Ordering, No Commission',
                'og_description' => 'A professional QR menu and direct ordering channel your restaurant fully controls.',
                'og_image' => '',
            ],

            'contact' => [
                'email' => 'hello@xorder.app',
                'whatsapp' => '',
            ],

            'footer' => [
                'tagline' => $bi('QR menus and direct ordering, made simple.', 'قوائم QR وطلب مباشر، ببساطة.'),
                'rights' => $bi('All rights reserved.', 'جميع الحقوق محفوظة.'),
            ],
        ];
    }
}
