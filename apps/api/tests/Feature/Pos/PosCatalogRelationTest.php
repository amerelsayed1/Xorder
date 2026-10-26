<?php

namespace Tests\Feature\Pos;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;

/**
 * XORD-014: the product/category relation as the till receives it. The POS
 * seeder drops any product whose category is not in the bundle (it would trip
 * the pos_products foreign key), so the bundle must never carry one, and must
 * never carry another tenant's rows.
 */
class PosCatalogRelationTest extends PosTestCase
{
    private function catalog(string $token): array
    {
        return $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token))->assertOk()->json('catalog');
    }

    public function test_every_item_in_the_bundle_names_a_category_in_the_bundle(): void
    {
        $drinks = Category::factory()->for($this->restaurant)->create();
        $food = Category::factory()->for($this->restaurant)->create();
        MenuItem::factory()->count(2)->for($this->restaurant)->for($drinks)->create();
        MenuItem::factory()->for($this->restaurant)->for($food)->create();

        ['token' => $token] = $this->claimTerminal();
        $catalog = $this->catalog($token);

        $categoryIds = collect($catalog['categories']['data'])->pluck('id');
        $this->assertCount(2, $categoryIds);
        $this->assertCount(3, $catalog['items']['data']);
        foreach ($catalog['items']['data'] as $item) {
            $this->assertTrue($categoryIds->contains($item['category_id']), 'item '.$item['id'].' names a category the bundle lacks');
        }
    }

    public function test_deleting_a_category_removes_it_and_its_items_from_the_bundle_together(): void
    {
        $gone = Category::factory()->for($this->restaurant)->create();
        $kept = Category::factory()->for($this->restaurant)->create();
        $goneItem = MenuItem::factory()->for($this->restaurant)->for($gone)->create();
        $keptItem = MenuItem::factory()->for($this->restaurant)->for($kept)->create();

        ['token' => $token] = $this->claimTerminal();
        $this->actingAs($this->owner)->deleteJson("/api/dashboard/categories/{$gone->id}")->assertOk();

        $catalog = $this->catalog($token);

        $this->assertSame([$kept->id], collect($catalog['categories']['data'])->pluck('id')->all());
        $this->assertSame([$keptItem->id], collect($catalog['items']['data'])->pluck('id')->all());
        $this->assertNotContains($goneItem->id, collect($catalog['items']['data'])->pluck('id')->all());
    }

    public function test_the_bundle_carries_no_other_restaurants_categories_or_items(): void
    {
        $mine = Category::factory()->for($this->restaurant)->create();
        MenuItem::factory()->for($this->restaurant)->for($mine)->create();
        $other = Restaurant::factory()->create();
        $theirs = Category::factory()->for($other)->create();
        MenuItem::factory()->for($other)->for($theirs)->create();

        ['token' => $token] = $this->claimTerminal();
        $catalog = $this->catalog($token);

        $this->assertSame([$mine->id], collect($catalog['categories']['data'])->pluck('id')->all());
        $this->assertCount(1, $catalog['items']['data']);
        $this->assertSame($mine->id, $catalog['items']['data'][0]['category_id']);
    }
}
