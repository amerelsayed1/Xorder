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
     * then. Positioning: QR menu + direct ordering + no commission + easy setup.
     */
    public static function defaultContent(): array
    {
        $bi = fn (string $en, string $ar) => static::bi($en, $ar);

        return [
            'hero' => [
                'badge' => $bi('QR menu · Direct ordering · No commission', 'قائمة QR · طلب مباشر · بدون عمولة'),
                'title' => $bi(
                    'QR Menu & Direct Ordering System for Restaurants',
                    'نظام قائمة QR والطلب المباشر للمطاعم'
                ),
                'sub' => $bi(
                    'Create a professional digital menu for your restaurant or cafe, let customers order directly from their phones straight to your WhatsApp, and manage orders easily — without paying commission on every order.',
                    'أنشئ قائمة رقمية احترافية لمطعمك أو مقهاك، ودع عملاءك يطلبون مباشرة من هواتفهم إلى واتساب مطعمك، وأدر الطلبات بسهولة — دون دفع عمولة على كل طلب.'
                ),
                'cta' => $bi('Request a Demo', 'اطلب عرضاً توضيحياً'),
                'primary_link' => '#lead',
                'secondary' => $bi('View Live Menu Demo', 'شاهد القائمة الحية'),
                'secondary_link' => '',
                'value_points' => [
                    $bi('No commission on orders', 'بدون عمولة على الطلبات'),
                    $bi('QR menu ready to share', 'قائمة QR جاهزة للمشاركة'),
                    $bi('Easy menu updates', 'تحديث سهل للقائمة'),
                    $bi('Direct customer orders', 'طلبات مباشرة من العملاء'),
                ],
                // Kept so rows saved before value_points existed still resolve.
                'no_commission_label' => $bi('No commission on orders', 'بدون عمولة على الطلبات'),
                'ready_label' => $bi('QR menu ready to share', 'قائمة QR جاهزة للمشاركة'),
                'whatsapp_label' => $bi('Chat on WhatsApp', 'تواصل عبر واتساب'),
            ],

            'proof' => [
                ['title' => $bi('0%', '٠٪'), 'text' => $bi('Commission per order', 'عمولة على كل طلب')],
                ['title' => $bi('WhatsApp', 'واتساب'), 'text' => $bi('Orders sent straight to you', 'الطلبات تصلك مباشرة')],
                ['title' => $bi('No app', 'بدون تطبيق'), 'text' => $bi('Customers just scan', 'يكفي أن يمسح العملاء')],
            ],

            'offer' => [
                'title' => $bi('Start With a Professional QR Menu', 'ابدأ بقائمة QR احترافية'),
                'text' => $bi(
                    'Launch a clean, mobile-friendly QR menu for your restaurant or cafe. Add your categories, products, prices, images, and restaurant information, then share it with customers using a QR code or a direct link.',
                    'أطلق قائمة QR أنيقة وسهلة الاستخدام على الهاتف لمطعمك أو مقهاك. أضف الأقسام والمنتجات والأسعار والصور ومعلومات المطعم، ثم شاركها مع عملائك عبر رمز QR أو رابط مباشر.'
                ),
                'items' => [
                    ['icon' => '▦', 'text' => $bi('Replace printed and PDF menus', 'استبدل القوائم المطبوعة وملفات PDF')],
                    ['icon' => '✎', 'text' => $bi('Update prices and items anytime', 'حدّث الأسعار والأصناف في أي وقت')],
                    ['icon' => '✦', 'text' => $bi('Show product photos and descriptions', 'اعرض صور المنتجات وأوصافها')],
                    ['icon' => '↗', 'text' => $bi('Share by QR code, WhatsApp, or social media', 'شارك عبر رمز QR أو واتساب أو السوشيال ميديا')],
                    ['icon' => '✆', 'text' => $bi('Give customers a better mobile experience', 'امنح عملاءك تجربة أفضل على الهاتف')],
                ],
            ],

            'problem' => [
                'title' => $bi('Still Managing Your Menu and Orders Manually?', 'ما زلت تدير قائمتك وطلباتك يدوياً؟'),
                'sub' => $bi('The everyday headaches of running a menu the old way.', 'المتاعب اليومية لإدارة القائمة بالطريقة القديمة.'),
                'problems' => [
                    ['text' => $bi('Sending menu images or PDFs on WhatsApp', 'إرسال صور القائمة أو ملفات PDF على واتساب')],
                    ['text' => $bi('Reprinting menus whenever prices change', 'إعادة طباعة القوائم كلما تغيّرت الأسعار')],
                    ['text' => $bi('Receiving incomplete or messy orders', 'استقبال طلبات ناقصة أو غير منظمة')],
                    ['text' => $bi('Depending only on third-party platforms', 'الاعتماد فقط على المنصّات الوسيطة')],
                    ['text' => $bi('Paying commission while losing direct customer access', 'دفع العمولة وفقدان الوصول المباشر للعملاء')],
                ],
                'solution_title' => $bi('A simpler, more professional way', 'طريقة أبسط وأكثر احترافية'),
                'solution_text' => $bi(
                    'Xorder gives you a digital menu and direct ordering system that helps your restaurant look more professional, update faster, and receive orders in a more organized way.',
                    'يمنحك Xorder قائمة رقمية ونظام طلب مباشر يجعل مطعمك يبدو أكثر احترافية، ويحدّث أسرع، ويستقبل الطلبات بشكل أكثر تنظيماً.'
                ),
            ],

            // Direct ordering — how customers order and why it beats manual/third-party.
            'features' => [
                'title' => $bi('Receive Orders Directly From Your Customers', 'استقبل الطلبات مباشرة من عملائك'),
                'sub' => $bi(
                    'Let customers browse your menu, add items to the cart, and send their order straight to your restaurant’s WhatsApp — no app for you or your customers to install.',
                    'دع عملاءك يتصفحون قائمتك، ويضيفون الأصناف إلى السلة، ويرسلون طلبهم مباشرة إلى واتساب مطعمك — بدون تطبيق لك أو لعملائك.'
                ),
                'items' => [
                    ['icon' => '🛒', 'title' => $bi('Add to cart', 'أضف إلى السلة'), 'text' => $bi('Customers pick items and build their order right on their phone.', 'يختار العملاء الأصناف ويجهّزون طلبهم مباشرة من هواتفهم.')],
                    ['icon' => '✆', 'title' => $bi('Sent to your WhatsApp', 'تصلك على واتساب'), 'text' => $bi('The full order arrives on your WhatsApp, ready to confirm and prepare.', 'يصلك الطلب كاملاً على واتساب، جاهزاً للتأكيد والتحضير.')],
                    ['icon' => '🚗', 'title' => $bi('Pickup, delivery, or table', 'استلام أو توصيل أو طاولة'), 'text' => $bi('Support the order types that fit your restaurant (if available).', 'ادعم أنواع الطلبات التي تناسب مطعمك (إن وُجدت).')],
                    ['icon' => '✓', 'title' => $bi('Fewer order mistakes', 'أخطاء أقل في الطلبات'), 'text' => $bi('Clear, organized orders reduce manual errors and mix-ups.', 'طلبات واضحة ومنظمة تقلّل الأخطاء اليدوية والالتباس.')],
                    ['icon' => '♥', 'title' => $bi('Own your customers', 'عملاؤك ملكك'), 'text' => $bi('Keep the relationship with your restaurant, not a middleman.', 'احتفظ بعلاقتك المباشرة مع عملائك بدلاً من وسيط.')],
                    ['icon' => '％', 'title' => $bi('No commission', 'بدون عمولة'), 'text' => $bi('You never pay a percentage on any order.', 'لن تدفع نسبة على أي طلب أبداً.')],
                ],
            ],

            'no_commission' => [
                'title' => $bi('No Commission on Every Order', 'بدون عمولة على كل طلب'),
                'text' => $bi(
                    'With Xorder, customers order directly from your restaurant. Instead of losing a percentage on every order, you use your own direct ordering channel with a simple, predictable subscription.',
                    'مع Xorder يطلب العملاء مباشرة من مطعمك. وبدلاً من خسارة نسبة من كل طلب، تستخدم قناة طلب مباشرة خاصة بك باشتراك بسيط وثابت.'
                ),
                'third_party_title' => $bi('Third-party ordering platforms', 'منصّات الطلب الوسيطة'),
                'third_party' => [
                    ['text' => $bi('Charge commission on every order', 'تأخذ عمولة على كل طلب')],
                    ['text' => $bi('Limit your control over customers', 'تحدّ من تحكمك في عملائك')],
                    ['text' => $bi('Cost grows as your orders grow', 'تزيد التكلفة كلما زادت طلباتك')],
                ],
                'xorder_title' => $bi('Xorder', 'Xorder'),
                'xorder' => [
                    ['text' => $bi('No commission on orders', 'بدون عمولة على الطلبات')],
                    ['text' => $bi('Direct relationship with your customers', 'علاقة مباشرة مع عملائك')],
                    ['text' => $bi('Full control over your menu', 'تحكم كامل في قائمتك')],
                    ['text' => $bi('Branded ordering experience for your restaurant', 'تجربة طلب بهوية مطعمك')],
                ],
            ],

            'demo' => [
                'enabled' => true,
                'title' => $bi('Try the Customer Experience', 'جرّب تجربة العميل'),
                'text' => $bi(
                    'Open the live demo or scan the QR code to see how your customers will browse the menu, select items, and place an order from their phones.',
                    'افتح العرض الحي أو امسح رمز QR لترى كيف سيتصفح عملاؤك القائمة، ويختارون الأصناف، ويقدمون طلباً من هواتفهم.'
                ),
                'button' => $bi('Open Live Demo', 'افتح العرض الحي'),
                'restaurant_slug' => 'xorderrest',
            ],

            'steps' => [
                'title' => $bi('How Xorder Works', 'كيف يعمل Xorder'),
                'items' => [
                    ['title' => $bi('Create your digital menu', 'أنشئ قائمتك الرقمية'), 'text' => $bi('Add categories, items, prices, images, and your restaurant details.', 'أضف الأقسام والأصناف والأسعار والصور وتفاصيل مطعمك.')],
                    ['title' => $bi('Share your QR code or link', 'شارك رمز QR أو الرابط'), 'text' => $bi('Place the QR code on tables, packaging, social media, or WhatsApp.', 'ضع رمز QR على الطاولات أو التغليف أو السوشيال ميديا أو واتساب.')],
                    ['title' => $bi('Receive orders on WhatsApp', 'استقبل الطلبات على واتساب'), 'text' => $bi('Customers browse, select items, and send their order straight to your restaurant’s WhatsApp.', 'يتصفح العملاء ويختارون الأصناف ويرسلون طلبهم مباشرة إلى واتساب مطعمك.')],
                ],
            ],

            'pricing' => [
                'title' => $bi('Packages That Grow With You', 'باقات تنمو معك'),
                'sub' => $bi('Start with a QR menu, add direct ordering when you are ready.', 'ابدأ بقائمة QR، وأضف الطلب المباشر عندما تكون جاهزاً.'),
                'popular_label' => $bi('Recommended', 'موصى به'),
                'choose_label' => $bi('Request a Demo', 'اطلب عرضاً'),
                // Monthly/yearly toggle. Numbers below are placeholders anchored to
                // the one real price in the project (749 EGP) + the free tier; a
                // super admin can set the real amounts from Landing Management.
                'billing' => [
                    'monthly' => $bi('Monthly', 'شهري'),
                    'yearly' => $bi('Yearly', 'سنوي'),
                    'save' => $bi('2 months free', 'شهران مجاناً'),
                ],
                'plans' => [
                    [
                        'name' => $bi('Menu Starter', 'باقة القائمة'),
                        'subtitle' => $bi('Best for small cafes and restaurants that need a clean QR menu.', 'الأنسب للمقاهي والمطاعم الصغيرة التي تحتاج قائمة QR أنيقة.'),
                        'price_label' => $bi('Free', 'مجاني'),
                        'price_monthly' => $bi('Free', 'مجاني'),
                        'price_yearly' => $bi('Free', 'مجاني'),
                        'cta' => $bi('Start With QR Menu', 'ابدأ بقائمة QR'),
                        'recommended' => false,
                        'enabled' => true,
                        'features' => [
                            $bi('QR menu', 'قائمة QR'),
                            $bi('Menu categories', 'أقسام القائمة'),
                            $bi('Product images', 'صور المنتجات'),
                            $bi('Price and item updates', 'تحديث الأسعار والأصناف'),
                            $bi('Restaurant information page', 'صفحة معلومات المطعم'),
                            $bi('Shareable menu link', 'رابط قائمة قابل للمشاركة'),
                        ],
                    ],
                    [
                        'name' => $bi('Menu Plus', 'باقة القائمة بلس'),
                        'subtitle' => $bi('Best for restaurants that want customers to order directly from the menu.', 'الأنسب للمطاعم التي تريد أن يطلب العملاء مباشرة من القائمة.'),
                        'price_label' => $bi('749 EGP / mo', '٧٤٩ ج.م / شهر'),
                        'price_monthly' => $bi('749 EGP / mo', '٧٤٩ ج.م / شهر'),
                        'price_yearly' => $bi('7,490 EGP / yr', '٧٬٤٩٠ ج.م / سنة'),
                        'cta' => $bi('Request Menu Plus Demo', 'اطلب عرض القائمة بلس'),
                        'recommended' => true,
                        'enabled' => true,
                        'features' => [
                            $bi('Everything in Menu Starter', 'كل ما في باقة القائمة'),
                            $bi('Add to cart', 'إضافة إلى السلة'),
                            $bi('Direct order submission', 'إرسال الطلب مباشرة'),
                            $bi('Orders received on WhatsApp', 'استقبال الطلبات عبر واتساب'),
                            $bi('Pickup, delivery, or table orders (if available)', 'طلبات الاستلام أو التوصيل أو الطاولة (إن وُجدت)'),
                            $bi('Offers / coupons (if available)', 'العروض والكوبونات (إن وُجدت)'),
                        ],
                    ],
                    [
                        'name' => $bi('Restaurant Pro', 'باقة المطعم برو'),
                        'subtitle' => $bi('Best for restaurants that need a more complete ordering and management setup.', 'الأنسب للمطاعم التي تحتاج إعداداً أكمل للطلب والإدارة.'),
                        'price_label' => $bi('Custom pricing', 'تسعير مخصص'),
                        'price_monthly' => $bi('Custom pricing', 'تسعير مخصص'),
                        'price_yearly' => $bi('Custom pricing', 'تسعير مخصص'),
                        'cta' => $bi('Talk to Sales', 'تحدث مع المبيعات'),
                        'recommended' => false,
                        'enabled' => true,
                        'features' => [
                            $bi('Everything in Menu Plus', 'كل ما في باقة القائمة بلس'),
                            $bi('Order management dashboard', 'لوحة إدارة الطلبات'),
                            $bi('Delivery and pickup management', 'إدارة التوصيل والاستلام'),
                            $bi('Table ordering', 'الطلب من الطاولة'),
                            $bi('Reports and insights', 'التقارير والتحليلات'),
                            $bi('Branch support (if available)', 'دعم الفروع (إن وُجد)'),
                            $bi('Driver app (if available)', 'تطبيق السائق (إن وُجد)'),
                        ],
                    ],
                ],
            ],

            'industries' => [
                'title' => $bi('Built for Food Businesses of All Sizes', 'مصمم لأنشطة الطعام بكل أحجامها'),
                'sub' => $bi(
                    'Whether you run a small cafe or a growing restaurant brand, Xorder helps you present your menu professionally and receive orders directly from your customers.',
                    'سواء كنت تدير مقهى صغيراً أو علامة مطاعم متنامية، يساعدك Xorder على تقديم قائمتك باحترافية واستقبال الطلبات مباشرة من عملائك.'
                ),
                'items' => [
                    ['icon' => '🍽️', 'text' => $bi('Restaurants', 'المطاعم')],
                    ['icon' => '☕', 'text' => $bi('Cafes', 'المقاهي')],
                    ['icon' => '🧁', 'text' => $bi('Dessert shops', 'محلات الحلويات')],
                    ['icon' => '🍱', 'text' => $bi('Cloud kitchens', 'المطابخ السحابية')],
                    ['icon' => '🥡', 'text' => $bi('Takeaway restaurants', 'مطاعم الوجبات الجاهزة')],
                    ['icon' => '🚚', 'text' => $bi('Food trucks', 'عربات الطعام')],
                    ['icon' => '🏷️', 'text' => $bi('Local food brands', 'العلامات الغذائية المحلية')],
                ],
            ],

            'lead_form' => [
                'title' => $bi('Ready to Launch Your QR Menu?', 'جاهز لإطلاق قائمة QR الخاصة بك؟'),
                'sub' => $bi(
                    'Tell us about your restaurant and we’ll show you how Xorder can work for your menu, orders, and customer experience. No commitment — we’ll contact you to understand your needs and suggest the best setup.',
                    'أخبرنا عن مطعمك وسنوضح لك كيف يمكن أن يعمل Xorder مع قائمتك وطلباتك وتجربة عملائك. دون أي التزام — سنتواصل معك لفهم احتياجاتك واقتراح الإعداد الأنسب.'
                ),
                'button' => $bi('Request My Demo', 'اطلب عرضي التوضيحي'),
                'success' => $bi('Thanks! We received your request and will contact you shortly.', 'شكراً لك! استلمنا طلبك وسنتواصل معك قريباً.'),
            ],

            'cta' => [
                'title' => $bi('Start Receiving Direct Orders — Without Commission', 'ابدأ باستقبال الطلبات مباشرة — بدون عمولة'),
                'sub' => $bi(
                    'Give your customers a better ordering experience and keep more control over your orders, menu, and customer relationship.',
                    'امنح عملاءك تجربة طلب أفضل واحتفظ بتحكم أكبر في طلباتك وقائمتك وعلاقتك بعملائك.'
                ),
                'button' => $bi('Request a Demo', 'اطلب عرضاً توضيحياً'),
                'whatsapp_label' => $bi('WhatsApp', 'واتساب'),
            ],

            'whatsapp' => [
                'number' => '',
                'default_message' => $bi(
                    'Hi Xorder, I’d like a demo for my restaurant.',
                    'مرحباً Xorder، أرغب في عرض توضيحي لمطعمي.'
                ),
                'floating_enabled' => true,
                'hero_enabled' => true,
            ],

            'seo' => [
                'title' => $bi(
                    'Xorder | QR Menu & Direct Ordering System for Restaurants',
                    'Xorder | نظام قائمة QR والطلب المباشر للمطاعم'
                ),
                'description' => $bi(
                    'Create a professional QR menu for your restaurant, receive direct customer orders, and manage your menu easily without paying commission on every order.',
                    'أنشئ قائمة QR احترافية لمطعمك، واستقبل طلبات عملائك مباشرة، وأدر قائمتك بسهولة دون دفع عمولة على كل طلب.'
                ),
                'og_title' => $bi(
                    'QR Menu & Direct Ordering for Restaurants',
                    'قائمة QR والطلب المباشر للمطاعم'
                ),
                'og_description' => $bi(
                    'Launch a digital menu, share it with a QR code, and receive direct orders from your customers with Xorder.',
                    'أطلق قائمة رقمية، وشاركها عبر رمز QR، واستقبل طلبات عملائك مباشرة مع Xorder.'
                ),
                'og_image' => '',
            ],

            'contact' => [
                'email' => 'hello@xorder.app',
                'whatsapp' => '',
            ],

            'footer' => [
                'tagline' => $bi('QR menus and direct ordering for restaurants — no commission.', 'قوائم QR وطلب مباشر للمطاعم — بدون عمولة.'),
                'rights' => $bi('All rights reserved.', 'جميع الحقوق محفوظة.'),
            ],
        ];
    }
}
