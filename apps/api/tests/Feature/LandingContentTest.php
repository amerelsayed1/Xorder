<?php

namespace Tests\Feature;

use App\Models\LandingContent;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class LandingContentTest extends TestCase
{
    use RefreshDatabase;

    public function test_public_landing_content_exposes_all_sales_sections(): void
    {
        $this->getJson('/api/public/landing-content')
            ->assertOk()
            ->assertJsonStructure([
                'data' => [
                    'hero' => ['no_commission_label', 'ready_label'],
                    'offer' => ['items'],
                    'problem' => ['problems', 'solution_title'],
                    'no_commission' => ['third_party', 'xorder'],
                    'demo' => ['enabled', 'restaurant_slug'],
                    'pricing' => ['plans'],
                    'industries' => ['items'],
                    'lead_form' => ['title', 'success'],
                    'whatsapp' => ['number', 'floating_enabled'],
                    'seo' => ['title', 'description', 'og_title'],
                ],
            ]);
    }

    public function test_old_rows_gain_new_sections_via_fallback_merge(): void
    {
        // Simulate a row saved before the new sections existed.
        LandingContent::create(['content' => ['hero' => ['title' => ['en' => 'Legacy', 'ar' => '']]]]);

        $content = LandingContent::current()->content;

        $this->assertSame('Legacy', $content['hero']['title']['en']);
        $this->assertArrayHasKey('no_commission', $content);
        $this->assertArrayHasKey('seo', $content);
        $this->assertArrayHasKey('lead_form', $content);
    }

    public function test_editing_landing_content_requires_super_admin(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $payload = ['content' => LandingContent::defaultContent()];

        $this->putJson('/api/admin/landing-content', $payload)->assertUnauthorized();
        $this->actingAs($admin)->putJson('/api/admin/landing-content', $payload)->assertForbidden();
    }

    public function test_super_admin_can_save_extended_content(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $content = LandingContent::defaultContent();
        $content['seo']['title'] = ['en' => 'Edited title', 'ar' => 'عنوان معدل'];
        $content['pricing']['plans'][2]['enabled'] = false;

        $this->actingAs($sa)->putJson('/api/admin/landing-content', ['content' => $content])
            ->assertOk()
            ->assertJsonPath('data.seo.title.en', 'Edited title')
            ->assertJsonPath('data.seo.title.ar', 'عنوان معدل')
            ->assertJsonPath('data.pricing.plans.2.enabled', false);

        // Persisted and visible publicly.
        $this->getJson('/api/public/landing-content')
            ->assertJsonPath('data.seo.title.en', 'Edited title')
            ->assertJsonPath('data.pricing.plans.2.enabled', false);
    }
}
