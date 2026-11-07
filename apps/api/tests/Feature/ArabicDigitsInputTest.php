<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\PosLicence;
use App\Models\ReceiptProfile;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * XORD-004 — numbers typed with Arabic or Persian digits reach the API as the
 * number the person meant, and phone numbers are stored in Latin digits.
 */
class ArabicDigitsInputTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->restaurantAdmin(Restaurant::factory()->create()->id)->create();
    }

    public function test_a_price_in_arabic_digits_is_stored_as_the_number(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id,
            'name_en' => 'Koshary',
            'price' => '١٢٥٫٥٠',
            'discounted_price' => '١٠٠',
        ])->assertCreated();

        $item = MenuItem::query()->where('name_en', 'Koshary')->firstOrFail();
        $this->assertSame('125.50', (string) $item->price);
        $this->assertSame('100.00', (string) $item->discounted_price);
    }

    public function test_the_rules_still_apply_after_the_digits_are_folded(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        // lt:price is judged on the folded numbers: 120 is not below 100.
        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'X', 'price' => '١٠٠', 'discounted_price' => '١٢٠',
        ])->assertStatus(422)->assertJsonValidationErrors('discounted_price');
    }

    public function test_what_is_not_plainly_a_number_is_still_refused(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        foreach (['١٢أ', '١٬٢٥٠', 'abc'] as $bad) {
            $this->actingAs($admin)->postJson('/api/dashboard/items', [
                'category_id' => $cat->id, 'name_en' => 'X', 'price' => $bad,
            ])->assertStatus(422)->assertJsonValidationErrors('price');
        }
        $this->assertSame(0, MenuItem::query()->count());
    }

    public function test_option_prices_nested_in_an_item_are_folded_too(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id,
            'name_en' => 'Burger',
            'price' => '٥٠',
            'option_groups' => [[
                'name_en' => 'Extras',
                'options' => [['name_en' => 'Cheese', 'price' => '٧٫٥']],
            ]],
        ])->assertCreated();
    }

    public function test_receipt_and_licence_contact_phones_are_folded_keeping_the_leading_zero(): void
    {
        // Suppliers are deliberately stored verbatim (PurchasingFoundationsTest).
        // A receipt profile's phone and a licence's contact phone are plain
        // contact details, and the licence's is not part of the signed claims.
        $profile = new ReceiptProfile(['phone' => '٠١٠٠٠٠٠٠٠٠٠']);
        $profile->normalizePhoneFields();
        $this->assertSame('01000000000', $profile->phone);

        $licence = new PosLicence(['contact_phone' => '+٢٠١٠٠٠٠٠٠٠٠٠']);
        $licence->normalizePhoneFields();
        $this->assertSame('+201000000000', $licence->contact_phone);
    }
}
