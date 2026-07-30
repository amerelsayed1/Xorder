<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class MenuImportBilingualTest extends TestCase
{
    use RefreshDatabase;

    private const ID_HEADER = 'id,category_id,category_en,category_ar,name_en,name_ar,description_en,description_ar,price,discounted_price,available,featured,image_url';

    private const NAME_HEADER = 'category_en,category_ar,name_en,name_ar,description_en,description_ar,price,discounted_price,available,featured,image_url';

    private function upload(User $admin, string $header, string $body): TestResponse
    {
        $csv = "\xEF\xBB\xBF".$header."\n".$body;
        $file = UploadedFile::fake()->createWithContent('menu.csv', $csv);

        return $this->actingAs($admin)->postJson('/api/dashboard/items/import', ['file' => $file]);
    }

    private function admin(): User
    {
        $r = Restaurant::factory()->create(['bilingual' => true]);

        return User::factory()->restaurantAdmin($r->id)->create();
    }

    // --- backward-compat: name-keyed files (no id column) still work ---

    public function test_name_keyed_bilingual_csv_imports_both_languages(): void
    {
        $admin = $this->admin();

        $this->upload($admin, self::NAME_HEADER, implode("\n", [
            'SOFT DRINKS,مشروبات غازية,WATER,مياه,cold water,مياه معبأة باردة,15.00,,yes,no,',
            'BOBA,بوبا,BOBA MILK TEA,شاي حليب بالبوبا,creamy,شاي بالحليب,90.00,,yes,no,',
        ])."\n")->assertOk();

        $this->assertSame(2, Category::count());
        $this->assertSame(2, MenuItem::count());
        $water = MenuItem::where('name_en', 'WATER')->firstOrFail();
        $this->assertSame('مياه', $water->name_ar);
        $this->assertSame('مياه معبأة باردة', $water->description_ar);
    }

    public function test_name_keyed_reimport_updates_without_duplicating(): void
    {
        $admin = $this->admin();
        $body = "SOFT DRINKS,مشروبات غازية,WATER,مياه,en,ar,15.00,,yes,no,\n";

        $this->upload($admin, self::NAME_HEADER, $body)->assertOk();
        $this->upload($admin, self::NAME_HEADER, $body)->assertOk();

        $this->assertSame(1, Category::count());
        $this->assertSame(1, MenuItem::count());
    }

    // --- the fix: stable-id matching survives renames (the duplication bug) ---

    public function test_id_match_updates_item_even_when_name_changed(): void
    {
        $admin = $this->admin();
        $r = $admin->restaurant;
        $cat = Category::factory()->for($r)->create(['name_en' => 'SOFT DRINKS', 'name_ar' => null]);
        $item = MenuItem::factory()->for($r)->for($cat)->create(['name_en' => 'WATER', 'name_ar' => null, 'price' => 15]);

        // Same id, but the name was translated/changed — must update, not duplicate.
        $this->upload($admin, self::ID_HEADER,
            "{$item->id},{$cat->id},SOFT DRINKS,مشروبات غازية,Bottled Water,مياه,en,ar,15.00,,yes,no,\n"
        )->assertOk();

        $this->assertSame(1, MenuItem::count(), 'id match must update in place');
        $item->refresh();
        $this->assertSame('Bottled Water', $item->name_en);
        $this->assertSame('مياه', $item->name_ar);
    }

    public function test_category_id_match_renames_in_place_no_duplicate(): void
    {
        $admin = $this->admin();
        $r = $admin->restaurant;
        $cat = Category::factory()->for($r)->create(['name_en' => 'Iced Coffee', 'name_ar' => null]);
        $item = MenuItem::factory()->for($r)->for($cat)->create(['name_en' => 'Iced Latte', 'price' => 90]);

        $this->upload($admin, self::ID_HEADER,
            "{$item->id},{$cat->id},ICE COFFEE,آيس كوفي,Iced Latte,آيس لاتيه,en,ar,90.00,,yes,no,\n"
        )->assertOk();

        $this->assertSame(1, Category::count(), 'category id match must rename, not duplicate');
        $this->assertSame(1, MenuItem::count());
        $cat->refresh();
        $this->assertSame('ICE COFFEE', $cat->name_en);
        $this->assertSame('آيس كوفي', $cat->name_ar);
    }

    public function test_export_carries_stable_id_columns(): void
    {
        $admin = $this->admin();
        $r = $admin->restaurant;
        $cat = Category::factory()->for($r)->create(['name_en' => 'Drinks']);
        $item = MenuItem::factory()->for($r)->for($cat)->create(['name_en' => 'Water', 'price' => 10]);

        $res = $this->actingAs($admin)->get('/api/dashboard/items/export?format=csv');
        $res->assertOk();
        $csv = $res->streamedContent();

        $this->assertStringContainsString('id,category_id,category_en', $csv);
        $this->assertStringContainsString("{$item->id},{$cat->id},Drinks", $csv);
    }
}
