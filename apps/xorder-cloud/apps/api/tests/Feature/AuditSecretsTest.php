<?php

namespace Tests\Feature;

use App\Console\Commands\RedactActivitySecrets;
use App\Models\PosTerminal;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;
use Tests\TestCase;

/**
 * Credentials never reach the activity log — not through the dedicated
 * events, which always kept them out, and not through the generic "updated"
 * diff, which did not (16 Oct 2026): the cashier PIN's salt and hash were in
 * the file for anyone with audit.view, which is a four-digit PIN recovered in
 * seconds and a till signed into as somebody else.
 */
class AuditSecretsTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = storage_path('framework/testing/audit-secrets-'.uniqid());
        config([
            'platform.activity_log_file' => true,
            'logging.channels.activity.path' => $this->dir.'/activity.log',
        ]);
        Log::forgetChannel('activity');
    }

    protected function tearDown(): void
    {
        Log::forgetChannel('activity');
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    private function todaysFile(): string
    {
        return $this->dir.'/activity-'.now()->format('Y-m-d').'.log';
    }

    public function test_setting_a_pin_records_the_act_and_never_the_pair(): void
    {
        $restaurant = Restaurant::factory()->create(['slug' => 'demo']);
        // The PIN routes sit behind the POS plan feature.
        $restaurant->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);
        $admin = User::factory()->restaurantAdmin($restaurant->id)->create();

        $this->actingAs($admin)
            ->putJson("/api/dashboard/staff/{$admin->id}/pin", ['pin' => '4829'])
            ->assertOk();

        $admin->refresh();
        $log = file_get_contents($this->todaysFile());

        $this->assertStringContainsString('staff.pos_pin_set', $log);
        $this->assertStringNotContainsString('pos_pin_salt', $log);
        $this->assertStringNotContainsString('pos_pin_hash', $log);
        $this->assertStringNotContainsString($admin->pos_pin_hash, $log);
        $this->assertStringNotContainsString($admin->pos_pin_salt, $log);
    }

    public function test_hidden_and_excluded_columns_stay_out_of_every_models_diff(): void
    {
        $user = new User;
        foreach (['password', 'remember_token', 'pos_pin_salt', 'pos_pin_hash'] as $column) {
            $this->assertContains($column, $user->auditExcludedAttributes(), $column);
        }

        $terminal = new PosTerminal;
        foreach (['device_token_hash', 'previous_token_hash', 'register_response_cache', 'fingerprint'] as $column) {
            $this->assertContains($column, $terminal->auditExcludedAttributes(), $column);
        }
        // Still audits what the operator should see.
        $this->assertNotContains('state', $terminal->auditExcludedAttributes());
        $this->assertNotContains('name', $user->auditExcludedAttributes());
    }

    public function test_the_redaction_command_scrubs_what_was_already_written(): void
    {
        File::ensureDirectoryExists($this->dir);
        $leaked = json_encode([
            'ts' => '2026-10-16T02:36:40+00:00', 'action' => 'user.updated', 'tenant_id' => 16,
            'actor_id' => 17, 'actor_name' => 'المدير العام', 'actor_role' => 'RESTAURANT_ADMIN',
            'subject_type' => 'User', 'subject_id' => 21, 'ip' => '127.0.0.1',
            'description' => 'User "سارة" updated',
            'properties' => ['changes' => [
                'pos_pin_salt' => ['old' => null, 'new' => 'EuDYSrlsTNuN7AuZ/NvXgw=='],
                'pos_pin_hash' => ['old' => null, 'new' => '3O3Kdm/lXsljOQLzypVKW47c6kjS0OK36kXl1eY2uro='],
                'name' => ['old' => 'Sara', 'new' => 'سارة'],
            ]],
        ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        $clean = json_encode(['ts' => '2026-10-16T02:37:00+00:00', 'action' => 'auth.login', 'properties' => null]);
        file_put_contents($this->todaysFile(), $leaked."\n".$clean."\n");

        $this->artisan('activity:redact-secrets')->expectsOutputToContain('Redacted 1 line(s) in 1 file(s).');

        $lines = array_values(array_filter(explode("\n", file_get_contents($this->todaysFile()))));
        $this->assertCount(2, $lines);
        $event = json_decode($lines[0], true);
        $this->assertSame(RedactActivitySecrets::REDACTED, $event['properties']['changes']['pos_pin_hash']['new']);
        $this->assertSame(RedactActivitySecrets::REDACTED, $event['properties']['changes']['pos_pin_salt']['new']);
        $this->assertSame('سارة', $event['properties']['changes']['name']['new'], 'other changes are untouched');
        $this->assertSame('user.updated', $event['action']);
        $this->assertStringNotContainsString('3O3Kdm', file_get_contents($this->todaysFile()));
        $this->assertSame($clean, $lines[1], 'a line with nothing to redact is byte-identical');

        // Running it again changes nothing.
        $this->artisan('activity:redact-secrets')->expectsOutputToContain('Redacted 0 line(s) in 0 file(s).');
    }
}
