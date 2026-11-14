<?php

namespace Tests\Feature;

use App\Models\Lead;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class LeadTest extends TestCase
{
    use RefreshDatabase;

    public function test_public_can_submit_a_lead(): void
    {
        $this->postJson('/api/public/leads', [
            'restaurant_name' => 'Test Cafe',
            'contact_name' => 'Amer',
            'whatsapp' => '+201234567890',
            'city' => 'Cairo',
            'business_type' => 'Cafe',
            'message' => 'Want a demo',
            'source' => 'landing_lead_form',
        ])->assertCreated();

        $this->assertDatabaseHas('leads', [
            'restaurant_name' => 'Test Cafe',
            'status' => 'NEW',
            'source' => 'landing_lead_form',
        ]);
    }

    public function test_lead_submission_requires_name_and_whatsapp(): void
    {
        $this->postJson('/api/public/leads', ['contact_name' => 'x'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['restaurant_name', 'whatsapp']);
    }

    public function test_honeypot_submission_fakes_success_without_storing(): void
    {
        $this->postJson('/api/public/leads', [
            'restaurant_name' => 'Bot Cafe',
            'whatsapp' => '+201234567890',
            'website' => 'https://spam.example.com', // hidden field humans never fill
        ])->assertCreated();

        $this->assertDatabaseMissing('leads', ['restaurant_name' => 'Bot Cafe']);
    }

    public function test_leads_inbox_requires_super_admin(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->getJson('/api/admin/leads')->assertUnauthorized();
        $this->actingAs($admin)->getJson('/api/admin/leads')->assertForbidden();
    }

    public function test_super_admin_can_list_and_filter_leads(): void
    {
        $sa = User::factory()->superAdmin()->create();
        Lead::create(['restaurant_name' => 'Alpha', 'whatsapp' => '1', 'status' => 'NEW']);
        Lead::create(['restaurant_name' => 'Beta', 'whatsapp' => '2', 'status' => 'WON']);

        $this->actingAs($sa)->getJson('/api/admin/leads')
            ->assertOk()
            ->assertJsonPath('meta.total', 2)
            ->assertJsonCount(2, 'data');

        $this->actingAs($sa)->getJson('/api/admin/leads?status=WON')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.restaurant_name', 'Beta');
    }

    public function test_super_admin_can_update_status_and_notes(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $lead = Lead::create(['restaurant_name' => 'Alpha', 'whatsapp' => '1', 'status' => 'NEW']);

        $this->actingAs($sa)->patchJson("/api/admin/leads/{$lead->id}", [
            'status' => 'CONTACTED',
            'notes' => 'Called them',
        ])->assertOk()->assertJsonPath('data.status', 'CONTACTED');

        $this->assertDatabaseHas('leads', ['id' => $lead->id, 'status' => 'CONTACTED', 'notes' => 'Called them']);
    }

    public function test_lead_update_rejects_unknown_status(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $lead = Lead::create(['restaurant_name' => 'Alpha', 'whatsapp' => '1', 'status' => 'NEW']);

        $this->actingAs($sa)->patchJson("/api/admin/leads/{$lead->id}", ['status' => 'BOGUS'])
            ->assertStatus(422)->assertJsonValidationErrors('status');
    }

    public function test_super_admin_can_export_leads_as_csv(): void
    {
        $sa = User::factory()->superAdmin()->create();
        Lead::create(['restaurant_name' => 'Alpha', 'whatsapp' => '1', 'status' => 'NEW']);

        $res = $this->actingAs($sa)->get('/api/admin/leads/export');
        $res->assertOk();
        $this->assertStringContainsString('text/csv', $res->headers->get('content-type'));
        $this->assertStringContainsString('Alpha', $res->streamedContent());
    }
}
