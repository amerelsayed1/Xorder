<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The owner sets the menu's look from Settings (owner decision 2026-11-03):
 * the brand colour and the layout. The second colour, default language and
 * ordering channel stay Super-Admin-only.
 */
class RestaurantBrandingTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_change_brand_colour_and_menu_layout(): void
    {
        $r = Restaurant::factory()->create(['brand_color' => '#f89a06', 'menu_layout' => 'photo']);
        $owner = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', [
            'brand_color' => '#1E7A46',
            'menu_layout' => 'text-list',
        ])->assertOk()
            ->assertJsonPath('data.brand_color', '#1E7A46')
            ->assertJsonPath('data.menu_layout', 'text-list');

        // The diner sees it on the public menu.
        $this->getJson("/api/public/restaurants/{$r->slug}/branding")->assertOk();
        $fresh = $r->fresh();
        $this->assertSame('#1E7A46', $fresh->brand_color);
        $this->assertSame('text-list', $fresh->menu_layout->value);
    }

    public function test_colour_and_layout_are_validated(): void
    {
        $r = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['brand_color' => 'red'])
            ->assertStatus(422)->assertJsonValidationErrors(['brand_color']);
        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['brand_color' => '#12345'])
            ->assertStatus(422)->assertJsonValidationErrors(['brand_color']);
        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['menu_layout' => 'carousel'])
            ->assertStatus(422)->assertJsonValidationErrors(['menu_layout']);
        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['menu_layout' => null])
            ->assertStatus(422)->assertJsonValidationErrors(['menu_layout']);
    }

    public function test_the_colour_can_be_changed_but_not_cleared(): void
    {
        $r = Restaurant::factory()->create(['brand_color' => '#123456']);
        $owner = User::factory()->restaurantAdmin($r->id)->create();

        // The column is NOT NULL; an empty colour is a validation error, not a 500.
        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['brand_color' => null])
            ->assertStatus(422)->assertJsonValidationErrors(['brand_color']);
        $this->assertSame('#123456', $r->fresh()->brand_color);
    }

    public function test_changing_the_colour_tells_the_tills_and_saving_it_unchanged_does_not(): void
    {
        $r = Restaurant::factory()->create(['brand_color' => '#f89a06']);
        $owner = User::factory()->restaurantAdmin($r->id)->create();
        $before = (int) $r->fresh()->pos_config_version;

        // Same colour, different case: not a change, no re-download.
        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['brand_color' => '#F89A06'])->assertOk();
        $this->assertSame($before, (int) $r->fresh()->pos_config_version);

        // A new colour is the till's accent_hex, so the bundle version moves.
        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['brand_color' => '#0055aa'])->assertOk();
        $this->assertSame($before + 1, (int) $r->fresh()->pos_config_version);

        // A layout change is the web menu's business alone.
        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['menu_layout' => 'text-grid'])->assertOk();
        $this->assertSame($before + 1, (int) $r->fresh()->pos_config_version);
    }

    public function test_the_admin_only_fields_are_still_ignored(): void
    {
        $r = Restaurant::factory()->create(['secondary_color' => '#111111', 'default_language' => 'ar']);
        $owner = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', [
            'secondary_color' => '#999999',
            'default_language' => 'en',
        ])->assertOk();

        $fresh = $r->fresh();
        $this->assertSame('#111111', $fresh->secondary_color);
        $this->assertSame('ar', $fresh->default_language->value);
    }

    public function test_staff_without_settings_update_cannot_change_the_look(): void
    {
        $r = Restaurant::factory()->create(['brand_color' => '#f89a06']);
        $role = new Role(['name' => 'Viewer']);
        $role->forceFill(['restaurant_id' => $r->id, 'capabilities' => ['settings.view']])->save();
        $staff = User::factory()->staff($r->id, $role->id)->create();

        $this->actingAs($staff)->putJson('/api/dashboard/restaurant', ['brand_color' => '#000000'])
            ->assertForbidden();
        $this->assertSame('#f89a06', $r->fresh()->brand_color);
    }
}
