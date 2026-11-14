<?php

namespace Tests\Feature;

use App\Enums\TenantCapability;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * XORD-005 — which languages a restaurant writes its content in.
 *
 *   Arabic only  → Arabic required, English not asked for
 *   English only → English required, Arabic not asked for
 *   Both         → either, as before
 *
 * And switching a language off never erases the text already written in it.
 */
class ContentLanguagesTest extends TestCase
{
    use RefreshDatabase;

    private function owner(string $lang = 'ar', bool $bilingual = true): User
    {
        $restaurant = Restaurant::factory()->create(['default_language' => $lang, 'bilingual' => $bilingual]);

        return User::factory()->restaurantAdmin($restaurant->id)->create();
    }

    private function staffWith(Restaurant $restaurant, array $capabilities): User
    {
        $role = new Role(['name' => 'Role '.uniqid()]);
        $role->forceFill([
            'restaurant_id' => $restaurant->id,
            'capabilities' => TenantCapability::expand($capabilities),
            'is_system' => false,
        ])->save();

        return User::factory()->staff($restaurant->id, $role->id)->create();
    }

    // ------------------------------------------------------------- the setting

    // Owner decision, 2026-11-07: the business's content languages are set by
    // the Super Admin only. The owner's Profile save ignores them, as it does
    // the secondary colour and the ordering channel.
    public function test_the_owner_cannot_change_the_content_languages(): void
    {
        $owner = $this->owner('ar', true);
        $restaurant = $owner->restaurant;
        $before = (int) $restaurant->fresh()->pos_config_version;

        foreach ([
            ['bilingual' => false, 'default_language' => 'ar'],
            ['bilingual' => false, 'default_language' => 'en'],
            ['default_language' => 'fr'],
        ] as $attempt) {
            $this->actingAs($owner)->putJson('/api/dashboard/restaurant', $attempt)->assertOk();
            $fresh = $restaurant->fresh();
            $this->assertSame('ar', $fresh->default_language->value);
            $this->assertTrue((bool) $fresh->bilingual);
        }
        $this->assertSame($before, (int) $restaurant->fresh()->pos_config_version, 'nothing changed, the tills are not told');
    }

    public function test_staff_without_settings_update_still_cannot_save_the_profile(): void
    {
        $owner = $this->owner();
        $denied = $this->staffWith($owner->restaurant, ['settings.view']);

        $this->actingAs($denied)->putJson('/api/dashboard/restaurant', ['bilingual' => false])->assertForbidden();
        $this->assertTrue((bool) $owner->restaurant->fresh()->bilingual);
    }

    // ----------------------------------------------------------- what is required

    public function test_arabic_only_needs_the_arabic_name(): void
    {
        $owner = $this->owner('ar', false);

        $this->actingAs($owner)->postJson('/api/dashboard/categories', ['name_ar' => 'مشروبات'])->assertCreated();

        // English alone is not a name in a menu that is written in Arabic.
        $this->actingAs($owner)->postJson('/api/dashboard/categories', ['name_en' => 'Drinks'])
            ->assertUnprocessable()->assertJsonValidationErrors('name_ar');
    }

    public function test_english_only_needs_the_english_name(): void
    {
        $owner = $this->owner('en', false);

        $this->actingAs($owner)->postJson('/api/dashboard/categories', ['name_en' => 'Drinks'])->assertCreated();
        $this->actingAs($owner)->postJson('/api/dashboard/categories', ['name_ar' => 'مشروبات'])
            ->assertUnprocessable()->assertJsonValidationErrors('name_en');
    }

    public function test_both_languages_accept_either(): void
    {
        $owner = $this->owner('ar', true);

        $this->actingAs($owner)->postJson('/api/dashboard/categories', ['name_ar' => 'مشروبات'])->assertCreated();
        $this->actingAs($owner)->postJson('/api/dashboard/categories', ['name_en' => 'Drinks'])->assertCreated();
    }

    public function test_the_disabled_language_never_blocks_a_submit(): void
    {
        $owner = $this->owner('ar', false);
        $cat = Category::factory()->for($owner->restaurant)->create(['name_ar' => 'مشروبات', 'name_en' => null]);

        // The form is not showing English, so it sends it empty.
        $this->actingAs($owner)->putJson("/api/dashboard/categories/{$cat->id}", ['name_ar' => 'مشروبات باردة', 'name_en' => ''])
            ->assertOk();
    }

    public function test_clearing_the_visible_name_is_refused_even_if_a_hidden_translation_exists(): void
    {
        $owner = $this->owner('ar', false);
        $cat = Category::factory()->for($owner->restaurant)->create(['name_ar' => 'مشروبات', 'name_en' => 'Drinks']);

        $this->actingAs($owner)->putJson("/api/dashboard/categories/{$cat->id}", ['name_ar' => '', 'name_en' => 'Drinks'])
            ->assertUnprocessable()->assertJsonValidationErrors('name_ar');
    }

    // ------------------------------------------------------ nothing is erased

    public function test_editing_in_arabic_only_keeps_the_english_translation(): void
    {
        $owner = $this->owner('ar', false);
        $cat = Category::factory()->for($owner->restaurant)->create(['name_ar' => 'مشروبات', 'name_en' => 'Drinks']);

        // An older client or a script blanks the hidden language.
        $this->actingAs($owner)->putJson("/api/dashboard/categories/{$cat->id}", ['name_ar' => 'مشروبات باردة', 'name_en' => null])
            ->assertOk();

        $fresh = $cat->fresh();
        $this->assertSame('مشروبات باردة', $fresh->name_ar);
        $this->assertSame('Drinks', $fresh->name_en, 'the hidden translation survived');
    }

    public function test_a_translation_written_in_a_disabled_language_is_still_stored(): void
    {
        $owner = $this->owner('ar', false);
        $cat = Category::factory()->for($owner->restaurant)->create(['name_ar' => 'مشروبات', 'name_en' => 'Drinks']);

        $this->actingAs($owner)->putJson("/api/dashboard/categories/{$cat->id}", ['name_ar' => 'مشروبات', 'name_en' => 'Beverages'])
            ->assertOk();

        $this->assertSame('Beverages', $cat->fresh()->name_en);
    }

    public function test_menu_items_keep_the_hidden_name_and_description_too(): void
    {
        $owner = $this->owner('en', false);
        $item = MenuItem::factory()->for($owner->restaurant)->for(Category::factory()->for($owner->restaurant))
            ->create(['name_en' => 'Koshary', 'name_ar' => 'كشري', 'description_en' => 'Rice', 'description_ar' => 'أرز']);

        $this->actingAs($owner)->putJson("/api/dashboard/items/{$item->id}", [
            'name_en' => 'Koshary XL', 'name_ar' => '', 'description_ar' => null,
        ])->assertOk();

        $fresh = $item->fresh();
        $this->assertSame('Koshary XL', $fresh->name_en);
        $this->assertSame('كشري', $fresh->name_ar);
        $this->assertSame('أرز', $fresh->description_ar);
    }

    public function test_switching_a_language_off_and_on_again_loses_nothing(): void
    {
        $owner = $this->owner('ar', true);
        $cat = Category::factory()->for($owner->restaurant)->create(['name_ar' => 'مشروبات', 'name_en' => 'Drinks']);

        // Switched by the Super Admin (the owner cannot, see above).
        $owner->restaurant->update(['bilingual' => false]);
        $this->actingAs($owner)->putJson("/api/dashboard/categories/{$cat->id}", ['name_ar' => 'مشروبات', 'name_en' => null])->assertOk();
        $owner->restaurant->update(['bilingual' => true]);

        $this->assertSame('Drinks', $cat->fresh()->name_en);
    }

    public function test_the_restaurant_name_in_the_profile_follows_the_same_rule(): void
    {
        $owner = $this->owner('en', false);

        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['name_ar' => 'مطعم', 'name_en' => ''])
            ->assertUnprocessable()->assertJsonValidationErrors('name_en');
    }
}
