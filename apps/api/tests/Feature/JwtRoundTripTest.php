<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class JwtRoundTripTest extends TestCase
{
    use RefreshDatabase;

    private function login(): string
    {
        User::factory()->superAdmin()->create(['username' => 'superadmin']);

        return $this->postJson('/api/auth/login', ['username' => 'superadmin', 'password' => 'password'])
            ->assertOk()->json('token');
    }

    public function test_no_token_is_unauthorized(): void
    {
        $this->login();
        $this->getJson('/api/auth/me')->assertUnauthorized();
    }

    public function test_valid_token_authorizes(): void
    {
        $token = $this->login();
        $this->withHeaders(['Authorization' => "Bearer {$token}"])
            ->getJson('/api/auth/me')->assertOk()->assertJsonPath('data.role', 'SUPER_ADMIN');
    }

    public function test_forged_payload_is_unauthorized(): void
    {
        $token = $this->login();
        [$h, $p, $s] = explode('.', $token);
        $p[0] = $p[0] === 'A' ? 'B' : 'A';
        $this->withHeaders(['Authorization' => "Bearer {$h}.{$p}.{$s}"])
            ->getJson('/api/auth/me')->assertUnauthorized();
    }

    public function test_garbage_token_is_unauthorized(): void
    {
        $this->login();
        $this->withHeaders(['Authorization' => 'Bearer not.a.jwt'])
            ->getJson('/api/auth/me')->assertUnauthorized();
    }
}
