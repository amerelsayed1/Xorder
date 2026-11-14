<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BranchTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Branches are tenant-owned; route-model binding is scoped by the global
     * RestaurantScope, so cross-tenant edits/toggles/deletes must 404.
     */
    public function test_cannot_modify_another_restaurants_branch(): void
    {
        $rB = Restaurant::factory()->create();
        $branch = $rB->branches()->create(['name_en' => 'Bravo Main']);

        $adminA = User::factory()->restaurantAdmin(Restaurant::factory()->create()->id)->create();

        $this->actingAs($adminA)->putJson("/api/dashboard/branches/{$branch->id}", ['name_en' => 'Hacked'])
            ->assertNotFound();
        $this->actingAs($adminA)->patchJson("/api/dashboard/branches/{$branch->id}/status", ['is_open' => false])
            ->assertNotFound();
        $this->actingAs($adminA)->deleteJson("/api/dashboard/branches/{$branch->id}")
            ->assertNotFound();

        $this->assertDatabaseHas('branches', ['id' => $branch->id, 'name_en' => 'Bravo Main']);
    }
}
