<?php

namespace Tests\Feature;

use App\Enums\LanguageEnum;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The "name required" error must land on the restaurant's default-language name
 * field — that's the only name input a single-language menu form renders, so a
 * mismatched key (e.g. always name_en) would leave the error invisible.
 */
class NameRequiredErrorKeyTest extends TestCase
{
    use RefreshDatabase;

    private function adminFor(Restaurant $r): User
    {
        return User::factory()->restaurantAdmin($r->id)->create();
    }

    public function test_item_store_reports_name_error_on_default_language_field(): void
    {
        $r = Restaurant::factory()->create(['default_language' => LanguageEnum::AR]);
        $cat = Category::factory()->for($r)->create();
        $admin = $this->adminFor($r);

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'price' => 30,
        ])->assertStatus(422)
            ->assertJsonValidationErrors('name_ar')
            ->assertJsonMissingValidationErrors('name_en');
    }

    public function test_item_store_reports_name_error_in_english_for_english_menu(): void
    {
        $r = Restaurant::factory()->create(['default_language' => LanguageEnum::EN]);
        $cat = Category::factory()->for($r)->create();
        $admin = $this->adminFor($r);

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'price' => 30,
        ])->assertStatus(422)
            ->assertJsonValidationErrors('name_en')
            ->assertJsonMissingValidationErrors('name_ar');
    }

    public function test_item_update_reports_name_error_on_default_language_field(): void
    {
        $r = Restaurant::factory()->create(['default_language' => LanguageEnum::AR]);
        $cat = Category::factory()->for($r)->create();
        $item = MenuItem::factory()->for($r)->for($cat)->create();
        $admin = $this->adminFor($r);

        $this->actingAs($admin)->putJson("/api/dashboard/items/{$item->id}", [
            'name_ar' => '', 'name_en' => '',
        ])->assertStatus(422)
            ->assertJsonValidationErrors('name_ar')
            ->assertJsonMissingValidationErrors('name_en');
    }

    public function test_profile_reports_name_error_on_default_language_field(): void
    {
        $r = Restaurant::factory()->create(['default_language' => LanguageEnum::AR]);
        $admin = $this->adminFor($r);

        $this->actingAs($admin)->putJson('/api/dashboard/restaurant', [
            'name_ar' => '', 'name_en' => '',
        ])->assertStatus(422)
            ->assertJsonValidationErrors('name_ar')
            ->assertJsonMissingValidationErrors('name_en');
    }
}
