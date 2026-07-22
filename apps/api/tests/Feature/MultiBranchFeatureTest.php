<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The multi_branch capability gates *adding* branches. Restaurants without it
 * keep and can still edit their existing branch(es); only entitled plans may
 * create new ones (routes/api.php: feature:multi_branch on POST branches).
 */
class MultiBranchFeatureTest extends TestCase
{
    use RefreshDatabase;

    public function test_branch_create_forbidden_without_multi_branch_feature(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)
            ->postJson('/api/dashboard/branches', ['name_en' => 'Second'])
            ->assertStatus(403);
    }

    public function test_branch_create_allowed_with_multi_branch_feature(): void
    {
        $r = Restaurant::factory()->create();
        $r->features()->create(['feature_key' => 'multi_branch', 'is_enabled' => true]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)
            ->postJson('/api/dashboard/branches', ['name_en' => 'Second'])
            ->assertCreated();
    }

    public function test_existing_branch_editable_without_multi_branch_feature(): void
    {
        $r = Restaurant::factory()->create();
        $branch = $r->branches()->create(['name_en' => 'Main']);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)
            ->putJson("/api/dashboard/branches/{$branch->id}", ['name_en' => 'Renamed'])
            ->assertOk();
    }
}
