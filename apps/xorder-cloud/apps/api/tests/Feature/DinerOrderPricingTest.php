<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Combo;
use App\Models\ComboGroup;
use App\Models\ComboGroupItem;
use App\Models\MenuItem;
use App\Models\Option;
use App\Models\OptionGroup;
use App\Models\Order;
use App\Models\Restaurant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * XORD-047: a diner order is priced by the server, from the menu.
 *
 * The public menu used to post each line's `line_total` and the server added
 * them up, so a modified request could set any price. Every test here sends
 * the price the phone would like and checks the order carries the menu's.
 */
class DinerOrderPricingTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->withOrdering()->create(['slug' => 'priced']);
        $this->category = Category::factory()->create(['restaurant_id' => $this->restaurant->id]);
    }

    private function item(array $attributes = [], ?Restaurant $restaurant = null): MenuItem
    {
        $restaurant ??= $this->restaurant;
        $category = $restaurant->is($this->restaurant)
            ? $this->category
            : Category::factory()->create(['restaurant_id' => $restaurant->id]);

        return MenuItem::factory()->create($attributes + [
            'restaurant_id' => $restaurant->id,
            'category_id' => $category->id,
            'name_en' => 'Burger',
            'name_ar' => 'برجر',
            'price' => 100,
        ]);
    }

    private function group(MenuItem $item, array $attributes): OptionGroup
    {
        $group = new OptionGroup($attributes + ['menu_item_id' => $item->id, 'max_select' => 1]);
        $group->restaurant_id = $item->restaurant_id;
        $group->save();

        return $group;
    }

    private function option(OptionGroup $group, array $attributes): Option
    {
        $option = new Option($attributes + ['option_group_id' => $group->id, 'is_available' => true]);
        $option->restaurant_id = $group->restaurant_id;
        $option->save();

        return $option;
    }

    private function order(array $lines, array $extra = [])
    {
        return $this->postJson('/api/public/restaurants/priced/orders', $extra + [
            'items' => $lines,
            'customer_name' => 'Nour',
            'customer_phone' => '+201234567890',
        ]);
    }

    private function onlyOrder(): Order
    {
        return Order::withoutGlobalScopes()->where('restaurant_id', $this->restaurant->id)->sole();
    }

    public function test_a_tampered_price_is_charged_at_the_menu_price(): void
    {
        $burger = $this->item(['price' => 100]);

        $this->order([[
            'kind' => 'item', 'menu_item_id' => $burger->id, 'qty' => 2,
            'name' => 'Free burger', 'line_total' => 0.01,
        ]], ['total' => 0.01, 'lang' => 'en'])->assertCreated();

        $order = $this->onlyOrder();
        $this->assertEquals(200.00, (float) $order->total);
        $this->assertSame('200.00', $order->items[0]['line_total']);
        $this->assertSame('100.00', $order->items[0]['unit_price']);
        $this->assertSame('Burger', $order->items[0]['name'], 'named by the menu, not the phone');
        $this->assertSame('server', $order->items[0]['price_source']);
        $this->assertDatabaseHas('order_items', [
            'order_id' => $order->id, 'menu_item_id' => $burger->id,
            'unit_price_minor' => 10000, 'line_total_minor' => 20000, 'price_source' => 'server',
        ]);
    }

    public function test_the_menu_arithmetic_sale_price_size_and_add_on(): void
    {
        // The card quotes the sale price; a size replaces it; an add-on adds
        // its LIST price — exactly what apps/menu useCart.calculateLinePrice does.
        $pizza = $this->item(['name_en' => 'Pizza', 'price' => 120, 'discounted_price' => 99]);
        $sizes = $this->group($pizza, ['name_en' => 'Size', 'name_ar' => 'الحجم', 'is_variant' => true]);
        $this->option($sizes, ['name_en' => 'Small', 'name_ar' => 'صغير', 'price' => 90]);
        $large = $this->option($sizes, ['name_en' => 'Large', 'name_ar' => 'كبير', 'price' => 150, 'discounted_price' => 140]);
        $extras = $this->group($pizza, ['name_en' => 'Extras', 'name_ar' => 'إضافات', 'max_select' => 3]);
        $cheese = $this->option($extras, ['name_en' => 'Cheese', 'name_ar' => 'جبنة', 'price' => 15, 'discounted_price' => 5]);
        $plain = $this->item(['name_en' => 'Plain', 'price' => 50, 'discounted_price' => 40]);

        $this->order([
            ['kind' => 'item', 'menu_item_id' => $pizza->id, 'qty' => 2, 'option_ids' => [$large->id, $cheese->id]],
            ['kind' => 'item', 'menu_item_id' => $plain->id, 'qty' => 1],
        ], ['lang' => 'ar'])->assertCreated();

        $order = $this->onlyOrder();
        // (140 + 15) × 2 = 310, plus 40 = 350.
        $this->assertSame('310.00', $order->items[0]['line_total']);
        $this->assertSame('كبير', $order->items[0]['variant']);
        $this->assertSame(['جبنة'], $order->items[0]['options']);
        $this->assertSame('40.00', $order->items[1]['line_total']);
        $this->assertEquals(350.00, (float) $order->total);
    }

    public function test_a_combo_is_priced_from_its_base_and_choices(): void
    {
        $burger = $this->item(['name_en' => 'Burger']);
        $fries = $this->item(['name_en' => 'Fries']);
        $cola = $this->item(['name_en' => 'Cola']);

        $combo = new Combo(['name_en' => 'Meal', 'name_ar' => 'وجبة', 'base_price' => 150, 'is_active' => true]);
        $combo->restaurant_id = $this->restaurant->id;
        $combo->save();
        $mains = new ComboGroup(['combo_id' => $combo->id, 'name_en' => 'Main', 'max_select' => 1, 'is_variant' => false]);
        $mains->restaurant_id = $this->restaurant->id;
        $mains->save();
        $drinks = new ComboGroup(['combo_id' => $combo->id, 'name_en' => 'Drink', 'max_select' => 1, 'is_variant' => false]);
        $drinks->restaurant_id = $this->restaurant->id;
        $drinks->save();
        $pick = function (ComboGroup $group, MenuItem $item, float $extra) {
            $choice = new ComboGroupItem(['combo_group_id' => $group->id, 'menu_item_id' => $item->id, 'extra_price' => $extra]);
            $choice->restaurant_id = $this->restaurant->id;
            $choice->save();

            return $choice;
        };
        $withBurger = $pick($mains, $burger, 0);
        $pick($mains, $fries, 0);
        $withCola = $pick($drinks, $cola, 10);

        $this->order([[
            'kind' => 'combo', 'combo_id' => $combo->id, 'qty' => 1,
            'option_ids' => [$withBurger->id, $withCola->id], 'line_total' => 1,
        ]])->assertCreated();

        $this->assertSame('160.00', $this->onlyOrder()->items[0]['line_total']);
    }

    public function test_an_order_from_an_old_menu_tab_is_told_to_refresh(): void
    {
        // What the menu sent before this release: names and prices, no ids.
        $this->order([['name' => 'Burger', 'qty' => 1, 'line_total' => 100]], ['total' => 100])
            ->assertStatus(422)
            ->assertJsonPath('message', __('xorder.messages.menu_refresh_required'));

        $this->assertDatabaseCount('orders', 0);
        $this->assertDatabaseCount('customers', 0);
    }

    public function test_another_restaurants_item_is_refused_and_nothing_written(): void
    {
        $foreign = $this->item([], Restaurant::factory()->withOrdering()->create());

        $this->order([['kind' => 'item', 'menu_item_id' => $foreign->id, 'qty' => 1]])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['items.0.menu_item_id']);

        $this->assertDatabaseCount('orders', 0);
        $this->assertDatabaseCount('customers', 0);
    }

    public function test_an_unavailable_deleted_or_hidden_item_is_refused(): void
    {
        $off = $this->item(['is_available' => false]);
        $gone = $this->item();
        $gone->delete();
        $hidden = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => Category::factory()->inactive()->create(['restaurant_id' => $this->restaurant->id])->id,
        ]);

        foreach ([$off, $gone, $hidden] as $item) {
            $this->order([['kind' => 'item', 'menu_item_id' => $item->id, 'qty' => 1]])
                ->assertStatus(422);
        }
        $this->assertDatabaseCount('orders', 0);
    }

    public function test_an_option_that_is_off_or_belongs_to_another_item_is_refused(): void
    {
        $pizza = $this->item();
        $extras = $this->group($pizza, ['name_en' => 'Extras', 'max_select' => 3]);
        $off = $this->option($extras, ['name_en' => 'Truffle', 'price' => 50, 'is_available' => false]);

        $other = $this->item();
        $theirs = $this->option($this->group($other, ['name_en' => 'Extras', 'max_select' => 3]), ['name_en' => 'Egg', 'price' => 5]);

        foreach ([$off, $theirs] as $option) {
            $this->order([['kind' => 'item', 'menu_item_id' => $pizza->id, 'qty' => 1, 'option_ids' => [$option->id]]])
                ->assertStatus(422)
                ->assertJsonValidationErrors(['items.0.option_ids']);
        }
        $this->assertDatabaseCount('orders', 0);
    }

    public function test_a_size_must_be_chosen_and_only_one(): void
    {
        $pizza = $this->item();
        $sizes = $this->group($pizza, ['name_en' => 'Size', 'is_variant' => true]);
        $small = $this->option($sizes, ['name_en' => 'Small', 'price' => 90]);
        $large = $this->option($sizes, ['name_en' => 'Large', 'price' => 150]);

        $this->order([['kind' => 'item', 'menu_item_id' => $pizza->id, 'qty' => 1]])
            ->assertStatus(422);
        $this->order([['kind' => 'item', 'menu_item_id' => $pizza->id, 'qty' => 1, 'option_ids' => [$small->id, $large->id]]])
            ->assertStatus(422);
        $this->assertDatabaseCount('orders', 0);
    }

    public function test_the_public_menu_names_options_and_combo_choices_by_id(): void
    {
        $pizza = $this->item();
        $extras = $this->group($pizza, ['name_en' => 'Extras', 'max_select' => 3]);
        $cheese = $this->option($extras, ['name_en' => 'Cheese', 'price' => 15]);

        $this->getJson('/api/public/restaurants/priced/menu')
            ->assertOk()
            ->assertJsonFragment(['id' => $cheese->id, 'name_en' => 'Cheese']);
    }
}
