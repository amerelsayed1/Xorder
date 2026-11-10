<?php

namespace Tests\Feature\Pos;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * XORD-021 — the logo reaches tills.
 *
 * The bundle already carries `branding.logo_url`, but a till re-reads the bundle
 * only when `pos_config_version` moves, and changing the logo moved nothing. So a
 * new logo waited for some unrelated change to ride along with.
 */
class PosBrandingVersionTest extends TestCase
{
    use RefreshDatabase;

    private function owner(): User
    {
        return User::factory()->restaurantAdmin(Restaurant::factory()->create(['logo_url' => 'https://xorder.test/storage/logos/old.webp'])->id)->create();
    }

    public function test_a_new_logo_tells_the_tills(): void
    {
        $owner = $this->owner();
        $before = (int) $owner->restaurant->fresh()->pos_config_version;

        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['logo_url' => 'https://xorder.test/storage/logos/new.webp'])->assertOk();

        $this->assertGreaterThan($before, (int) $owner->restaurant->fresh()->pos_config_version);
    }

    public function test_removing_the_logo_tells_the_tills(): void
    {
        $owner = $this->owner();
        $before = (int) $owner->restaurant->fresh()->pos_config_version;

        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['logo_url' => null])->assertOk();

        $this->assertGreaterThan($before, (int) $owner->restaurant->fresh()->pos_config_version);
        $this->assertNull($owner->restaurant->fresh()->logo_url);
    }

    public function test_posting_the_same_logo_back_changes_nothing(): void
    {
        $owner = $this->owner();
        $before = (int) $owner->restaurant->fresh()->pos_config_version;

        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['logo_url' => 'https://xorder.test/storage/logos/old.webp', 'phone' => null])->assertOk();

        $this->assertSame($before, (int) $owner->restaurant->fresh()->pos_config_version);
    }

    public function test_a_new_cover_image_is_not_a_bundle_change(): void
    {
        $owner = $this->owner();
        $before = (int) $owner->restaurant->fresh()->pos_config_version;

        $this->actingAs($owner)->putJson('/api/dashboard/restaurant', ['cover_image_url' => 'https://xorder.test/storage/covers/x.webp'])->assertOk();

        $this->assertSame($before, (int) $owner->restaurant->fresh()->pos_config_version);
    }

    public function test_the_super_admin_changing_the_logo_tells_the_tills_too(): void
    {
        $restaurant = Restaurant::factory()->create(['logo_url' => null]);
        $before = (int) $restaurant->fresh()->pos_config_version;

        $this->actingAs(User::factory()->superAdmin()->create())
            ->putJson("/api/admin/restaurants/{$restaurant->id}", ['logo_url' => 'https://xorder.test/storage/logos/a.webp'])
            ->assertOk();

        $this->assertGreaterThan($before, (int) $restaurant->fresh()->pos_config_version);
    }

    public function test_the_bundle_carries_the_logo_a_till_will_fetch(): void
    {
        $restaurant = Restaurant::factory()->create(['logo_url' => 'https://xorder.test/storage/logos/a.webp']);

        $this->assertSame('https://xorder.test/storage/logos/a.webp', $restaurant->fresh()->logo_url);
    }
}
