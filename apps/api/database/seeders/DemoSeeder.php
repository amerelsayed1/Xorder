<?php

namespace Database\Seeders;

use App\Enums\LanguageEnum;
use App\Enums\RoleEnum;
use App\Enums\SubscriptionStatus;
use App\Enums\UserStatus;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class DemoSeeder extends Seeder
{
    /**
     * Retired demo tenants are removed whenever this idempotent seeder runs,
     * keeping Mahsoub as the only showcase restaurant across deployments.
     */
    private array $retiredSlugs = [
        'demo', 'xorderrest', 'nakhla-cafe', 'saffron-house', 'olea-mezze',
        'cedar-coal', 'beit-aleppo',
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

        $this->seedMahsoub();
        $this->removeRetiredDemoTenants();

        $this->command?->info('Demo seeded: Mahsoub (/r/mahsoub-restaurnt).');
    }

    /**
     * Delete the retired demo tenants and their seeded owner accounts.
     * Categories, menu items, combos, branches and options cascade with the
     * restaurant; owner users must go first (their FK nulls on delete).
     * Idempotent — a no-op once they are gone.
     */
    private function removeRetiredDemoTenants(): void
    {
        $ids = Restaurant::whereIn('slug', $this->retiredSlugs)->pluck('id');
        if ($ids->isEmpty()) {
            return;
        }

        User::whereIn('restaurant_id', $ids)
            ->where('role', RoleEnum::RESTAURANT_ADMIN)
            ->delete();
        Restaurant::whereIn('id', $ids)->delete();

        $this->command?->info("Removed {$ids->count()} retired demo tenant(s).");
    }

    private function seedMahsoub(): void
    {
        $r = Restaurant::updateOrCreate(['slug' => 'mahsoub-restaurnt'], [
            'name_en' => 'Mahsoub', 'name_ar' => 'محسوب',
            'description_en' => 'Mahsoub is a modern Cairo restaurant serving fresh mezze, charcoal grills and homemade oriental sweets.',
            'description_ar' => 'محسوب مطعم قاهري عصري يقدم المقبلات الطازجة والمشاوي على الفحم والحلويات الشرقية المنزلية.',
            'phone' => '+20 100 555 0192', 'whatsapp_number' => '+201005550192',
            'address' => 'Cairo, Egypt', 'opening_hours' => 'Daily · 12:00 – 23:30',
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

        $this->admin($r, 'owner@mahsoub.test', 'Mahsoub Owner');

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

    private function admin(Restaurant $r, string $email, string $name): void
    {
        // Showcase tenants are for public menu display only — no one signs in as
        // them. Never seed a guessable password: a real, loginable
        // RESTAURANT_ADMIN with password "password" would be tenant takeover in
        // production. Use a fresh random secret (rotated every seed run); a
        // Super Admin can reset it on the rare occasion login is needed.
        $admin = User::firstOrNew(['email' => $email]);
        // forceFill: role/restaurant_id are guarded and only set in trusted code.
        $admin->forceFill([
            'name' => $name,
            'username' => mb_strtolower(explode('@', $email)[0]),
            'password' => Hash::make(Str::password(24)),
            'role' => RoleEnum::RESTAURANT_ADMIN,
            'restaurant_id' => $r->id,
            'status' => UserStatus::ACTIVE,
            'email_verified_at' => now(),
        ])->save();
    }
}
