<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Menu export (CSV / XLSX).
 *
 * Two things matter here beyond "it returns a file": the export must not carry
 * another tenant's menu, and it must not hand the owner a spreadsheet that
 * executes something when they open it — much of the text originates from
 * unauthenticated public input.
 */
class MenuExportTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private User $admin;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE]);
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
        $this->category = Category::factory()->create([
            'restaurant_id' => $this->restaurant->id, 'name_en' => 'Mezze', 'is_active' => true,
        ]);
    }

    private function item(array $attributes = []): MenuItem
    {
        return MenuItem::factory()->create($attributes + [
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $this->category->id,
        ]);
    }

    private function csv(): string
    {
        $res = $this->actingAs($this->admin)->get('/api/dashboard/items/export?format=csv');
        $res->assertOk();

        return $this->streamed($res);
    }

    private function streamed($res): string
    {
        ob_start();
        $res->baseResponse->sendContent();

        return ob_get_clean();
    }

    public function test_the_export_contains_the_restaurants_items(): void
    {
        $this->item(['name_en' => 'Hummus Beiruti', 'price' => 120]);

        $csv = $this->csv();

        $this->assertStringContainsString('Hummus Beiruti', $csv);
        $this->assertStringContainsString('Mezze', $csv);
    }

    public function test_the_export_never_includes_another_tenants_menu(): void
    {
        $this->item(['name_en' => 'Mine']);

        $other = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE]);
        $theirCategory = Category::factory()->create(['restaurant_id' => $other->id, 'is_active' => true]);
        MenuItem::factory()->create([
            'restaurant_id' => $other->id,
            'category_id' => $theirCategory->id,
            'name_en' => 'TheirSecretDish',
        ]);

        $csv = $this->csv();

        $this->assertStringContainsString('Mine', $csv);
        $this->assertStringNotContainsString('TheirSecretDish', $csv);
    }

    public function test_a_formula_in_an_item_name_is_defused_before_it_reaches_the_sheet(): void
    {
        // CWE-1236. An item name can reach the database from public input, and
        // Excel executes a leading "=" on open — so the export must neutralise
        // it rather than trusting the source.
        $this->item(['name_en' => '=HYPERLINK("http://evil.test","click")']);

        $csv = $this->csv();

        $this->assertStringContainsString("'=HYPERLINK", $csv, 'the cell must be quoted into text');
        $this->assertDoesNotMatchRegularExpression(
            '/(^|,|")=HYPERLINK/m',
            $csv,
            'no cell may start with a bare = once written'
        );
    }

    public function test_xlsx_is_offered_as_well_as_csv(): void
    {
        $this->item();

        $this->actingAs($this->admin)
            ->get('/api/dashboard/items/export?format=xlsx')
            ->assertOk();
    }

    public function test_the_export_requires_authentication(): void
    {
        $this->getJson('/api/dashboard/items/export?format=csv')->assertUnauthorized();
    }
}
