<?php

namespace Tests\Feature;

use App\Enums\SubscriptionStatus;
use App\Models\Restaurant;
use App\Models\User;
use App\Notifications\RestaurantAdminCredentials;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

class SignupTest extends TestCase
{
    use RefreshDatabase;

    private function payload(): array
    {
        return [
            'restaurant_name' => 'Tasty Corner',
            'restaurant_name_ar' => 'الركن اللذيذ',
            'name' => 'Amer',
            'email' => 'owner@tasty.example',
            'whatsapp' => '+201234567890',
        ];
    }

    public function test_signup_is_hidden_when_flag_is_off(): void
    {
        config(['platform.self_serve_signup' => false]);

        $this->postJson('/api/public/signup', $this->payload())->assertNotFound();
    }

    public function test_signup_provisions_restaurant_admin_and_trial(): void
    {
        Notification::fake();
        config(['platform.self_serve_signup' => true, 'platform.signup_trial_days' => 14]);

        $res = $this->postJson('/api/public/signup', $this->payload());

        $res->assertCreated()
            ->assertJsonPath('data.trial_days', 14)
            ->assertJsonStructure(['data' => ['public_url', 'login_url']]);

        $restaurant = Restaurant::where('name_en', 'Tasty Corner')->firstOrFail();
        $this->assertSame('tasty-corner', $restaurant->slug);
        $this->assertSame(SubscriptionStatus::TRIAL, $restaurant->subscription_status);
        $this->assertSame(now()->addDays(14)->toDateString(), $restaurant->subscription_end_date->toDateString());

        $admin = User::where('email', 'owner@tasty.example')->firstOrFail();
        $this->assertSame($restaurant->id, $admin->restaurant_id);
        $this->assertTrue($admin->isRestaurantAdmin());

        Notification::assertSentTo($admin, RestaurantAdminCredentials::class);
    }

    public function test_signup_honeypot_fakes_success(): void
    {
        config(['platform.self_serve_signup' => true]);

        $this->postJson('/api/public/signup', $this->payload() + ['website' => 'https://spam.example'])
            ->assertCreated();

        $this->assertDatabaseMissing('restaurants', ['name_en' => 'Tasty Corner']);
    }

    public function test_signup_rejects_duplicate_email(): void
    {
        config(['platform.self_serve_signup' => true]);
        User::factory()->create(['email' => 'owner@tasty.example']);

        $this->postJson('/api/public/signup', $this->payload())
            ->assertStatus(422)
            ->assertJsonValidationErrors(['email']);
    }

    public function test_arabic_name_gets_transliterated_slug(): void
    {
        config(['platform.self_serve_signup' => true]);

        $this->postJson('/api/public/signup', array_merge($this->payload(), [
            'restaurant_name' => 'مطعم الركن',
        ]))->assertCreated();

        $restaurant = Restaurant::where('name_en', 'مطعم الركن')->firstOrFail();
        // Str::slug transliterates Arabic; names that slugify to '' fall back
        // to a random r-xxxxxx handle instead.
        $this->assertMatchesRegularExpression('/^[a-z0-9][a-z0-9-]*$/', $restaurant->slug);
        $this->assertNotSame('', $restaurant->slug);
    }
}
