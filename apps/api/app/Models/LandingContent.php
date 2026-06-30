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
     */
    public static function current(): self
    {
        return static::firstOrCreate([], ['content' => static::defaultContent()]);
    }

    /**
     * A bilingual value: ['en' => ..., 'ar' => ...].
     */
    private static function bi(string $en, string $ar): array
    {
        return ['en' => $en, 'ar' => $ar];
    }

    /**
     * Default content mirroring the original hardcoded landing page, so the site
     * renders identically until a super admin customizes it.
     */
    public static function defaultContent(): array
    {
        $bi = fn (string $en, string $ar) => static::bi($en, $ar);

        return [
            'hero' => [
                'badge' => $bi('Contactless menus for modern restaurants', 'قوائم رقمية بدون لمس للمطاعم العصرية'),
                'title' => $bi('Your menu, a scan away.', 'قائمتك على بُعد مسح ضوئي.'),
                'sub' => $bi(
                    'Create a beautiful bilingual digital menu, print one QR code, and update prices and dishes in real time — no app, no reprints.',
                    'أنشئ قائمة رقمية ثنائية اللغة، اطبع رمز QR واحداً، وحدّث الأسعار والأصناف لحظياً — بدون تطبيق وبدون إعادة طباعة.'
                ),
                'cta' => $bi('Contact us', 'تواصل معنا'),
                'secondary' => $bi('See a live menu', 'شاهد قائمة حية'),
            ],

            'proof' => [
                ['title' => $bi('AR + EN', 'عربي + إنجليزي'), 'text' => $bi('Built for bilingual menus', 'مصمم للقوائم ثنائية اللغة')],
                ['title' => $bi('No app', 'بدون تطبيق'), 'text' => $bi('Guests open it instantly', 'يفتحه الضيوف فوراً')],
                ['title' => $bi('Live edits', 'تحديث حي'), 'text' => $bi('Prices update in seconds', 'تتغير الأسعار خلال ثوانٍ')],
            ],

            'features' => [
                'title' => $bi('Everything you need to go digital', 'كل ما تحتاجه للتحول الرقمي'),
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

            'steps' => [
                'title' => $bi('Live in three steps', 'انطلق في ثلاث خطوات'),
                'items' => [
                    ['title' => $bi('Build your menu', 'ابنِ قائمتك'), 'text' => $bi('Add categories, dishes, prices and photos from the dashboard.', 'أضف الأقسام والأطباق والأسعار والصور من لوحة التحكم.')],
                    ['title' => $bi('Print your QR', 'اطبع رمزك'), 'text' => $bi('Download your unique QR code and place it on tables or the storefront.', 'حمّل رمز QR الخاص بك وضعه على الطاولات أو الواجهة.')],
                    ['title' => $bi('Customers scan', 'العملاء يمسحون'), 'text' => $bi('Guests browse your live menu on their phone — no app to install.', 'يتصفح الضيوف قائمتك الحية على هواتفهم — بدون تطبيق.')],
                ],
            ],

            'pricing' => [
                'title' => $bi('Simple, honest pricing', 'أسعار بسيطة وصادقة'),
                'sub' => $bi('Start free. Upgrade when you grow.', 'ابدأ مجاناً. ترقَّ عندما تنمو.'),
                'popular_label' => $bi('Most popular', 'الأكثر شيوعاً'),
                'choose_label' => $bi('Choose plan', 'اختر الخطة'),
                'plans' => [
                    [
                        'name' => $bi('Starter', 'المبتدئ'),
                        'price' => $bi('Free', 'مجاني'),
                        'per' => $bi('', ''),
                        'note' => $bi('For a single location getting started.', 'لفرع واحد في بداية الطريق.'),
                        'popular' => false,
                        'features' => [
                            $bi('1 digital menu', 'قائمة رقمية واحدة'),
                            $bi('Unlimited dishes', 'أصناف غير محدودة'),
                            $bi('QR code', 'رمز QR'),
                            $bi('Bilingual menu', 'قائمة ثنائية اللغة'),
                        ],
                    ],
                    [
                        'name' => $bi('Professional', 'الاحترافي'),
                        'price' => $bi('$19', '٧٤٩ ج.م'),
                        'per' => $bi('/mo', '/شهرياً'),
                        'note' => $bi('For growing restaurants that want their brand.', 'للمطاعم النامية التي تريد هويتها.'),
                        'popular' => true,
                        'features' => [
                            $bi('1 digital menu', 'قائمة رقمية واحدة'),
                            $bi('Unlimited dishes', 'أصناف غير محدودة'),
                            $bi('QR code', 'رمز QR'),
                            $bi('Bilingual menu', 'قائمة ثنائية اللغة'),
                            $bi('Custom branding', 'هوية مخصصة'),
                            $bi('Priority support', 'دعم بأولوية'),
                            $bi('Scan analytics', 'تحليلات المسح'),
                        ],
                    ],
                ],
            ],

            'cta' => [
                'title' => $bi('Get in touch', 'تواصل معنا'),
                'sub' => $bi('Tell us about your restaurant and we’ll set up your digital menu.', 'أخبرنا عن مطعمك وسنجهّز قائمتك الرقمية.'),
                'button' => $bi('Contact us', 'تواصل معنا'),
                'whatsapp_label' => $bi('WhatsApp', 'واتساب'),
            ],

            'contact' => [
                'email' => 'hello@xorder.app',
                'whatsapp' => '',
            ],

            'footer' => [
                'tagline' => $bi('Digital menus made simple.', 'قوائم رقمية ببساطة.'),
                'rights' => $bi('All rights reserved.', 'جميع الحقوق محفوظة.'),
            ],
        ];
    }
}
