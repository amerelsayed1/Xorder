<?php

namespace Tests\Feature;

use App\Models\DeviceToken;
use App\Models\Restaurant;
use App\Models\User;
use App\Support\CsvSafe;
use App\Support\Jwt;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Password;
use Tests\TestCase;

/**
 * Regression coverage for the pre-launch security audit fixes:
 * JWT-invalidation-on-password-change, password-reset enumeration, CSV formula
 * injection, User privilege mass-assignment, and the fail-closed Super Admin
 * seeder.
 */
class SecurityHardeningTest extends TestCase
{
    use RefreshDatabase;

    // ── JWT invalidation on password change ────────────────────────────────

    public function test_token_issued_before_password_change_is_rejected(): void
    {
        $user = User::factory()->superAdmin()->create();
        $token = Jwt::issue($user); // iat = now

        // Simulate a password reset that happens strictly after the token was
        // minted (a stolen token the victim is trying to invalidate).
        $user->forceFill(['password_changed_at' => now()->addMinute()])->save();

        // The pre-change token must be rejected by the guard.
        $this->withHeaders(['Authorization' => "Bearer {$token}"])
            ->getJson('/api/auth/me')->assertUnauthorized();
    }

    public function test_token_issued_after_password_change_still_works(): void
    {
        $user = User::factory()->superAdmin()->create(['password_changed_at' => now()->subDay()]);
        $token = Jwt::issue($user);

        $this->withHeaders(['Authorization' => "Bearer {$token}"])
            ->getJson('/api/auth/me')->assertOk();
    }

    // ── Password reset ─────────────────────────────────────────────────────

    public function test_password_reset_stamps_password_changed_at(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'reset-co']);
        $user = User::factory()->restaurantAdmin($r->id)->create([
            'email' => 'owner@reset-co.test',
            'password_changed_at' => null,
        ]);
        $token = Password::createToken($user);

        $this->postJson('http://reset-co.example.com/api/auth/reset-password', [
            'token' => $token,
            'email' => 'owner@reset-co.test',
            'password' => 'BrandNewStrongPass9',
            'password_confirmation' => 'BrandNewStrongPass9',
        ])->assertOk();

        $this->assertNotNull($user->fresh()->password_changed_at);
    }

    public function test_password_reset_failure_is_generic_and_does_not_enumerate(): void
    {
        // Unknown email + bad token must NOT reveal whether the account exists;
        // the response is a single generic message either way.
        $unknown = $this->postJson('/api/auth/reset-password', [
            'token' => 'invalid-token',
            'email' => 'nobody@example.com',
            'password' => 'BrandNewStrongPass9',
            'password_confirmation' => 'BrandNewStrongPass9',
        ])->assertStatus(422)->json('message');

        $r = Restaurant::factory()->create();
        User::factory()->restaurantAdmin($r->id)->create(['email' => 'real@example.com']);

        $existing = $this->postJson('/api/auth/reset-password', [
            'token' => 'invalid-token',
            'email' => 'real@example.com',
            'password' => 'BrandNewStrongPass9',
            'password_confirmation' => 'BrandNewStrongPass9',
        ])->assertStatus(422)->json('message');

        // Same message for both → no user-enumeration oracle.
        $this->assertSame($unknown, $existing);
    }

    public function test_forgot_password_for_existing_user_does_not_error_or_enumerate(): void
    {
        // Regression: sendResetLink() used to throw RouteNotFoundException for a
        // real account (no reset-URL callback was registered), which both broke
        // reset and leaked user existence — a registered email 500'd while an
        // unknown one returned the generic 200. Both must now be a plain 200.
        $r = Restaurant::factory()->create(['slug' => 'forgot-co']);
        User::factory()->restaurantAdmin($r->id)->create(['email' => 'owner@forgot-co.test']);

        $this->postJson('/api/auth/forgot-password', ['email' => 'owner@forgot-co.test'])
            ->assertOk();

        $this->postJson('/api/auth/forgot-password', ['email' => 'ghost@nope.test'])
            ->assertOk();

        // A real reset link was actually issued (proves the notification rendered
        // without throwing, not just that validation passed).
        $this->assertDatabaseHas('password_reset_tokens', ['email' => 'owner@forgot-co.test']);
    }

    public function test_reset_link_points_at_the_tenant_dashboard(): void
    {
        Notification::fake();

        $r = Restaurant::factory()->create(['slug' => 'linkco']);
        $user = User::factory()->restaurantAdmin($r->id)->create(['email' => 'owner@linkco.test']);

        $this->postJson('/api/auth/forgot-password', ['email' => 'owner@linkco.test'])
            ->assertOk();

        Notification::assertSentTo($user, ResetPassword::class, function ($notification) use ($user) {
            $url = $notification->toMail($user)->actionUrl;

            return str_contains($url, '/reset-password')
                && str_contains($url, 'token='.$notification->token)
                && str_contains($url, 'email='.urlencode($user->email));
        });
    }

    public function test_reset_rejects_weak_password(): void
    {
        $r = Restaurant::factory()->create();
        $user = User::factory()->restaurantAdmin($r->id)->create(['email' => 'weak@example.com']);
        $token = Password::createToken($user);

        $this->postJson('/api/auth/reset-password', [
            'token' => $token,
            'email' => 'weak@example.com',
            'password' => 'short',
            'password_confirmation' => 'short',
        ])->assertStatus(422)->assertJsonValidationErrors('password');
    }

    // ── Login rate limiting (per-account) ──────────────────────────────────

    public function test_login_is_rate_limited_per_account(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'lockme']);
        User::factory()->restaurantAdmin($r->id)->create([
            'username' => 'target',
            'password' => 'correct-horse-9',
        ]);

        // 5 wrong attempts per (username, IP) are allowed; the 6th is throttled.
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('http://lockme.example.com/api/auth/login', [
                'username' => 'target', 'password' => 'wrong',
            ])->assertStatus(401);
        }

        $this->postJson('http://lockme.example.com/api/auth/login', [
            'username' => 'target', 'password' => 'wrong',
        ])->assertStatus(429);
    }

    // ── Device-token hijack ────────────────────────────────────────────────

    public function test_device_token_cannot_be_hijacked_by_another_user(): void
    {
        $rA = Restaurant::factory()->create();
        $userA = User::factory()->restaurantAdmin($rA->id)->create();
        $rB = Restaurant::factory()->create();
        $userB = User::factory()->restaurantAdmin($rB->id)->create();

        $this->actingAs($userA)->postJson('/api/dashboard/push/token', ['token' => 'device-xyz'])
            ->assertOk();

        // User B (another tenant) attempts to claim A's token — must be refused.
        $this->actingAs($userB)->postJson('/api/dashboard/push/token', ['token' => 'device-xyz'])
            ->assertOk();

        $row = DeviceToken::where('token', 'device-xyz')->first();
        $this->assertSame($userA->id, $row->user_id);
        $this->assertSame($rA->id, $row->restaurant_id);
    }

    // ── User privilege mass-assignment ─────────────────────────────────────

    public function test_role_and_restaurant_id_are_not_mass_assignable(): void
    {
        $r = Restaurant::factory()->create();

        $user = new User;
        $user->fill([
            'name' => 'Attacker',
            'username' => 'attacker',
            'email' => 'attacker@example.com',
            'password' => 'secret-password',
            'role' => 'SUPER_ADMIN',
            'restaurant_id' => $r->id,
            'status' => 'ACTIVE',
        ]);

        // Guarded attributes were dropped by fill().
        $this->assertNull($user->role);
        $this->assertNull($user->restaurant_id);
    }

    // ── CSV formula injection ──────────────────────────────────────────────

    public function test_csv_safe_neutralises_formula_prefixes(): void
    {
        $this->assertSame("'=cmd|'/c calc'!A1", CsvSafe::cell("=cmd|'/c calc'!A1"));
        $this->assertSame("'+1234", CsvSafe::cell('+1234'));
        $this->assertSame("'-2+3", CsvSafe::cell('-2+3'));
        $this->assertSame("'@SUM(A1)", CsvSafe::cell('@SUM(A1)'));

        // Ordinary values are untouched; non-strings pass through.
        $this->assertSame('Latte', CsvSafe::cell('Latte'));
        $this->assertSame('7.50', CsvSafe::cell('7.50'));
        $this->assertSame(42, CsvSafe::cell(42));
        $this->assertSame('', CsvSafe::cell(''));
    }

    // ── Fail-closed Super Admin seeder ─────────────────────────────────────

    public function test_seeder_refuses_empty_super_admin_password(): void
    {
        config(['platform.super_admin.password' => '']);

        $this->expectException(\RuntimeException::class);

        (new DatabaseSeeder)->run();
    }
}
