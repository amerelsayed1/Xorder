<?php

namespace Database\Seeders;

use App\Enums\LanguageEnum;
use App\Enums\RestaurantStatus;
use App\Enums\RoleEnum;
use App\Enums\SubscriptionStatus;
use App\Enums\UserStatus;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DemoSeeder extends Seeder
{
    /** Pool of real food photo ids (from the design handoff). */
    private array $pool = [
        'photo-1432139555190-58524dae6a55', 'photo-1455619452474-d2be8b1e70cd',
        'photo-1467003909585-2f8a72700288', 'photo-1490645935967-10de6ba17061',
        'photo-1504674900247-0877df9cc836', 'photo-1512621776951-a57141f2eefd',
        'photo-1519676867240-f03562e64548', 'photo-1529006557810-274b9b2fc783',
        'photo-1540189549336-e6e99c3679fe', 'photo-1544025162-d76694265947',
        'photo-1488477181946-6428a0291777', 'photo-1414235077428-338989a2e8c0',
    ];

    private function img(string $id, int $w = 800, ?int $h = null): string
    {
        $hp = $h ? "&h={$h}" : '';

        return "https://images.unsplash.com/{$id}?auto=format&fit=crop&w={$w}{$hp}&q=70";
    }

    private function logo(string $id): string
    {
        return $this->img($id, 200, 200);
    }

    public function run(): void
    {
        // Subscription plans catalog (also runs here so deploy.sh, which only
        // calls DemoSeeder, keeps /plans populated). Idempotent.
        $this->call(PlanSeeder::class);

        $this->seedXorderRest();

        // Additional tenants so the Super Admin list is populated — each with a
        // logo, cover, an admin, and a small menu (images included).
        // Subscription dates are relative to "now" so the Super Admin insights
        // (expiring in 7/30 days, past-end-date) always show realistic figures:
        // Cedar & Coal's trial expires within 7 days; Saffron/Beit Aleppo are past due.
        $extras = [
            ['name' => 'Nakhla Café', 'ar' => 'نخلة', 'slug' => 'nakhla-cafe', 'color' => '#1f7a3d',
                'status' => RestaurantStatus::ACTIVE, 'sub' => SubscriptionStatus::TRIAL, 'plan' => null,
                'start' => now()->subDays(4)->startOfDay(), 'end' => now()->addDays(10)->startOfDay(),
                'cover' => 'photo-1467003909585-2f8a72700288', 'logo' => 'photo-1455619452474-d2be8b1e70cd', 'city' => 'Sharjah'],
            ['name' => 'Saffron House', 'ar' => 'بيت الزعفران', 'slug' => 'saffron-house', 'color' => '#c46a1b',
                'status' => RestaurantStatus::SUSPENDED, 'sub' => SubscriptionStatus::EXPIRED, 'plan' => 'Restaurant Pro',
                'start' => now()->subDays(60)->startOfDay(), 'end' => now()->subDays(5)->startOfDay(),
                'cover' => 'photo-1504674900247-0877df9cc836', 'logo' => 'photo-1540189549336-e6e99c3679fe', 'city' => 'Dubai'],
            ['name' => 'Olea Mezze Bar', 'ar' => 'أوليا', 'slug' => 'olea-mezze', 'color' => '#3d4a7a',
                'status' => RestaurantStatus::ACTIVE, 'sub' => SubscriptionStatus::ACTIVE, 'plan' => 'Restaurant Pro',
                'start' => now()->subDays(30)->startOfDay(), 'end' => now()->addDays(335)->startOfDay(),
                'cover' => 'photo-1512621776951-a57141f2eefd', 'logo' => 'photo-1432139555190-58524dae6a55', 'city' => 'Abu Dhabi'],
            ['name' => 'Cedar & Coal', 'ar' => 'الأرز والفحم', 'slug' => 'cedar-coal', 'color' => '#7a4a2b',
                'status' => RestaurantStatus::ACTIVE, 'sub' => SubscriptionStatus::TRIAL, 'plan' => null,
                'start' => now()->subDays(9)->startOfDay(), 'end' => now()->addDays(5)->startOfDay(),
                'cover' => 'photo-1544025162-d76694265947', 'logo' => 'photo-1529006557810-274b9b2fc783', 'city' => 'Dubai'],
            ['name' => 'Beit Aleppo', 'ar' => 'بيت حلب', 'slug' => 'beit-aleppo', 'color' => '#6b748c',
                'status' => RestaurantStatus::ARCHIVED, 'sub' => SubscriptionStatus::SUSPENDED, 'plan' => 'Restaurant Pro',
                'start' => now()->subDays(120)->startOfDay(), 'end' => now()->subDays(30)->startOfDay(),
                'cover' => 'photo-1519676867240-f03562e64548', 'logo' => 'photo-1490645935967-10de6ba17061', 'city' => 'Cairo'],
        ];

        foreach ($extras as $x) {
            $this->seedRestaurant($x);
        }

        $this->command?->info('Demo seeded: XorderRest (/r/xorderrest) + 5 tenants for the Super Admin list.');
    }

    private function seedXorderRest(): void
    {
        // Replace the legacy 'demo' restaurant (formerly Zaytoun) in place on an
        // already-seeded database, so its menu is rebranded rather than duplicated.
        Restaurant::where('slug', 'demo')->update(['slug' => 'xorderrest']);

        $r = Restaurant::updateOrCreate(['slug' => 'xorderrest'], [
            'name_en' => 'XorderRest', 'name_ar' => 'إكس أوردر',
            'description_en' => 'The Xorder showcase restaurant — a modern Levantine kitchen with mezze, charcoal grills and homemade sweets, all on a live digital menu.',
            'description_ar' => 'مطعم إكس أوردر النموذجي — مطبخ شامي حديث من مقبلات ومشاوي على الفحم وحلويات منزلية، كله على قائمة رقمية حية.',
            'phone' => '+971 4 555 0192', 'whatsapp_number' => '+971455501920',
            'address' => 'Jumeirah 1, Dubai', 'opening_hours' => 'Daily · 12:00 – 23:30',
            'brand_color' => '#f89a06', 'secondary_color' => '#d9850a',
            'logo_url' => $this->logo('photo-1414235077428-338989a2e8c0'),
            'cover_image_url' => $this->img('photo-1414235077428-338989a2e8c0', 1400),
            'default_language' => LanguageEnum::AR,
            // Use the catalog plan name (not the legacy "Pro") and carry real
            // dates so the showcase tenant matches how an active subscription is
            // meant to look — and so expiry/renewal insights have data to work with.
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_plan' => 'Restaurant Pro',
            'subscription_start_date' => now()->startOfDay(),
            'subscription_end_date' => now()->addYear()->startOfDay(),
        ]);

        $this->admin($r, 'owner@xorderrest.test', 'XorderRest Owner');

        $menu = [
            ['Mezze', 'المقبلات', [
                ['Hummus Beiruti', 'حمص بيروتي', 18, null, 'photo-1455619452474-d2be8b1e70cd', true, 'Whipped chickpeas, garlic, chilli & toasted pine nuts.'],
                ['Muhammara', 'محمرة', 20, null, 'photo-1540189549336-e6e99c3679fe', false, 'Roasted red pepper, walnut & pomegranate.'],
                ['Moutabal', 'متبل', 19, null, 'photo-1512621776951-a57141f2eefd', false, 'Smoked aubergine, tahini & olive oil.'],
                ['Fattoush', 'فتوش', 22, 'na', 'photo-1490645935967-10de6ba17061', false, 'Garden greens, sumac & crisp pita.'],
            ]],
            ['From the Grill', 'من المشواة', [
                ['Shish Tawook', 'شيش طاووق', 42, null, 'photo-1529006557810-274b9b2fc783', false, 'Marinated chicken skewers, garlic toum.'],
                ['Lamb Kofta', 'كفتة لحم', 40, null, 'photo-1544025162-d76694265947', true, 'Spiced minced lamb, grilled tomato.'],
                ['Mixed Grill', 'مشاوي مشكّل', 65, 75, 'photo-1504674900247-0877df9cc836', true, 'Tawook, kofta & lamb chops. Serves two.'],
                ['Grilled Sea Bass', 'سمك مشوي', 58, null, 'photo-1519676867240-f03562e64548', false, 'Whole sea bass, lemon & herbs.'],
            ]],
            ['Sweets', 'الحلويات', [
                ['Baklava', 'بقلاوة', 24, null, 'photo-1467003909585-2f8a72700288', false, 'Layered filo, pistachio & honey.'],
                ['Knafeh', 'كنافة', 32, null, 'photo-1432139555190-58524dae6a55', true, 'Warm cheese pastry, sugar syrup.'],
                ['Muhalabia', 'مهلبية', 18, null, 'photo-1488477181946-6428a0291777', false, 'Rosewater milk pudding, pistachio.'],
            ]],
            ['Drinks', 'المشروبات', [
                ['Mint Lemonade', 'ليمون بالنعناع', 16, null, 'photo-1467003909585-2f8a72700288', false, null],
                ['Jallab', 'جلاب', 18, null, 'photo-1455619452474-d2be8b1e70cd', false, null],
            ]],
        ];

        foreach ($menu as $ci => [$en, $ar, $items]) {
            $cat = Category::updateOrCreate(
                ['restaurant_id' => $r->id, 'name_en' => $en],
                ['name_ar' => $ar, 'display_order' => $ci, 'is_active' => true],
            );
            foreach ($items as $ii => [$nen, $nar, $price, $old, $imgId, $featured, $desc]) {
                MenuItem::updateOrCreate(
                    ['restaurant_id' => $r->id, 'category_id' => $cat->id, 'name_en' => $nen],
                    [
                        'name_ar' => $nar, 'description_en' => $desc,
                        'price' => is_numeric($old) ? $old : $price,
                        'discounted_price' => is_numeric($old) ? $price : null,
                        'image_url' => $this->img($imgId),
                        'is_available' => $old !== 'na',
                        'is_featured' => (bool) $featured, 'display_order' => $ii,
                    ],
                );
            }
        }
    }

    /** Seed a secondary tenant with a logo, cover, admin and a small image-rich menu. */
    private function seedRestaurant(array $x): void
    {
        $r = Restaurant::updateOrCreate(['slug' => $x['slug']], [
            'name_en' => $x['name'], 'name_ar' => $x['ar'],
            'description_en' => "{$x['name']} — a Levantine table in {$x['city']}.",
            'description_ar' => 'مطعم شامي بنكهة أصيلة.',
            'phone' => '+971 4 555 0'.random_int(100, 999),
            'whatsapp_number' => '+9714555'.random_int(1000, 9999),
            'address' => $x['city'], 'opening_hours' => 'Daily · 11:00 – 23:00',
            'brand_color' => $x['color'],
            'logo_url' => $this->logo($x['logo']),
            'cover_image_url' => $this->img($x['cover'], 1400),
            'default_language' => LanguageEnum::AR,
            'status' => $x['status'],
            'subscription_status' => $x['sub'], 'subscription_plan' => $x['plan'],
            'subscription_start_date' => $x['start'] ?? null,
            'subscription_end_date' => $x['end'] ?? null,
        ]);

        $this->admin($r, 'owner@'.str_replace('-', '', $x['slug']).'.test', $x['name'].' Owner');

        $template = [
            ['Mezze', 'المقبلات', [['Hummus', 18], ['Falafel', 16], ['Tabbouleh', 19], ['Labneh', 17]]],
            ['Mains', 'الأطباق الرئيسية', [['Chicken Shawarma', 38], ['Lamb Mandi', 62], ['Veggie Platter', 34], ['Grilled Fish', 55]]],
            ['Drinks', 'المشروبات', [['Mint Lemonade', 16], ['Turkish Coffee', 14], ['Ayran', 12]]],
        ];

        $p = 0;
        foreach ($template as $ci => [$en, $ar, $items]) {
            $cat = Category::updateOrCreate(
                ['restaurant_id' => $r->id, 'name_en' => $en],
                ['name_ar' => $ar, 'display_order' => $ci, 'is_active' => true],
            );
            foreach ($items as $ii => [$nen, $price]) {
                MenuItem::updateOrCreate(
                    ['restaurant_id' => $r->id, 'category_id' => $cat->id, 'name_en' => $nen],
                    [
                        'price' => $price,
                        'image_url' => $this->img($this->pool[$p % count($this->pool)]),
                        'is_available' => $ii !== 3,
                        'is_featured' => $ii === 0,
                        'display_order' => $ii,
                    ],
                );
                $p++;
            }
        }
    }

    private function admin(Restaurant $r, string $email, string $name): void
    {
        User::updateOrCreate(['email' => $email], [
            'name' => $name,
            'password' => Hash::make('password'),
            'role' => RoleEnum::RESTAURANT_ADMIN,
            'restaurant_id' => $r->id,
            'status' => UserStatus::ACTIVE,
            'email_verified_at' => now(),
        ]);
    }
}
