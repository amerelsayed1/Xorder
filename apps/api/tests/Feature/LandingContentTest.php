<?php

namespace Tests\Feature;

use App\Models\LandingContent;
use App\Models\Plan;
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
        // SEO title is bilingual ({en, ar}) — edit both languages.
        $content['seo']['title'] = ['en' => 'Edited title', 'ar' => 'عنوان معدّل'];

        $this->actingAs($sa)->putJson('/api/admin/landing-content', ['content' => $content])
            ->assertOk()
            ->assertJsonPath('data.seo.title.en', 'Edited title')
            ->assertJsonPath('data.seo.title.ar', 'عنوان معدّل');

        // Persisted and visible publicly.
        $this->getJson('/api/public/landing-content')
            ->assertJsonPath('data.seo.title.en', 'Edited title');
    }

    public function test_public_pricing_is_generated_from_active_plans(): void
    {
        Plan::create(['name' => 'Starter', 'price' => 0, 'currency' => 'EGP', 'feature_keys' => ['qr_menu'], 'is_active' => true, 'sort_order' => 1]);
        Plan::create(['name' => 'Growth', 'price' => 749, 'currency' => 'EGP', 'feature_keys' => ['qr_menu', 'whatsapp_ordering', 'multi_branch'], 'max_branches' => 3, 'is_active' => true, 'is_recommended' => true, 'sort_order' => 2]);
        Plan::create(['name' => 'Pro', 'price' => null, 'currency' => 'EGP', 'feature_keys' => ['system_ordering'], 'is_active' => true, 'sort_order' => 3]);
        // Inactive plans never reach the marketing site.
        Plan::create(['name' => 'Hidden', 'currency' => 'EGP', 'is_active' => false, 'sort_order' => 4]);

        $this->getJson('/api/public/landing-content')
            ->assertOk()
            ->assertJsonCount(3, 'data.pricing.plans')
            ->assertJsonPath('data.pricing.plans.0.name', 'Starter')
            ->assertJsonPath('data.pricing.plans.0.price', 0)
            ->assertJsonPath('data.pricing.plans.0.currency', 'EGP')
            ->assertJsonPath('data.pricing.plans.1.name', 'Growth')
            ->assertJsonPath('data.pricing.plans.1.price', 749)
            ->assertJsonPath('data.pricing.plans.1.recommended', true)
            ->assertJsonPath('data.pricing.plans.1.max_branches', 3)
            ->assertJsonPath('data.pricing.plans.1.feature_keys', ['qr_menu', 'whatsapp_ordering', 'multi_branch'])
            ->assertJsonPath('data.pricing.plans.2.name', 'Pro')
            // Null price signals custom pricing to the landing app.
            ->assertJsonPath('data.pricing.plans.2.price', null)
            ->assertJsonPath('data.pricing.plans.2.recommended', false)
            // Plans carry a single price — the monthly/yearly toggle is dropped.
            ->assertJsonMissingPath('data.pricing.billing');
    }

    public function test_public_landing_content_includes_faq_section(): void
    {
        $this->getJson('/api/public/landing-content')
            ->assertOk()
            ->assertJsonStructure([
                'data' => [
                    'faq' => [
                        'title' => ['en', 'ar'],
                        'sub' => ['en', 'ar'],
                        'items' => [['enabled', 'q' => ['en', 'ar'], 'a' => ['en', 'ar']]],
                    ],
                ],
            ]);
    }

    public function test_super_admin_can_manage_faq_items_and_order_is_preserved(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $content = LandingContent::defaultContent();

        // Replace FAQ with a known, explicitly-ordered set; disable the middle one.
        $content['faq']['items'] = [
            ['enabled' => true, 'q' => ['en' => 'First?', 'ar' => 'الأول؟'], 'a' => ['en' => 'A1', 'ar' => 'ج1']],
            ['enabled' => false, 'q' => ['en' => 'Second?', 'ar' => 'الثاني؟'], 'a' => ['en' => 'A2', 'ar' => 'ج2']],
            ['enabled' => true, 'q' => ['en' => 'Third?', 'ar' => 'الثالث؟'], 'a' => ['en' => 'A3', 'ar' => 'ج3']],
        ];

        $this->actingAs($sa)->putJson('/api/admin/landing-content', ['content' => $content])
            ->assertOk()
            ->assertJsonPath('data.faq.items.0.q.en', 'First?')
            ->assertJsonPath('data.faq.items.1.enabled', false)
            ->assertJsonPath('data.faq.items.2.q.en', 'Third?');

        // Order and the disabled flag round-trip through the public endpoint.
        $this->getJson('/api/public/landing-content')
            ->assertJsonPath('data.faq.items.0.q.en', 'First?')
            ->assertJsonPath('data.faq.items.1.enabled', false)
            ->assertJsonPath('data.faq.items.2.q.en', 'Third?')
            ->assertJsonCount(3, 'data.faq.items');
    }

    public function test_faq_validation_rejects_invalid_items(): void
    {
        $sa = User::factory()->superAdmin()->create();

        // Missing the required boolean `enabled` flag.
        $content = LandingContent::defaultContent();
        $content['faq']['items'] = [['q' => ['en' => 'Q', 'ar' => ''], 'a' => ['en' => 'A', 'ar' => '']]];
        $this->actingAs($sa)->putJson('/api/admin/landing-content', ['content' => $content])
            ->assertStatus(422)
            ->assertJsonValidationErrors('content.faq.items.0.enabled');

        // Answer longer than the 2000-char cap.
        $content = LandingContent::defaultContent();
        $content['faq']['items'] = [['enabled' => true, 'q' => ['en' => 'Q', 'ar' => ''], 'a' => ['en' => str_repeat('x', 2001), 'ar' => '']]];
        $this->actingAs($sa)->putJson('/api/admin/landing-content', ['content' => $content])
            ->assertStatus(422)
            ->assertJsonValidationErrors('content.faq.items.0.a.en');
    }

    public function test_unknown_and_unsafe_keys_are_stripped_by_the_whitelist(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $content = LandingContent::defaultContent();
        // An attacker-style extra key with a script payload is not in the ruleset.
        $content['faq']['malicious'] = '<script>alert(1)</script>';
        $content['totally_unknown_section'] = ['foo' => 'bar'];

        $this->actingAs($sa)->putJson('/api/admin/landing-content', ['content' => $content])
            ->assertOk()
            ->assertJsonMissingPath('data.faq.malicious')
            ->assertJsonMissingPath('data.totally_unknown_section');

        $this->getJson('/api/public/landing-content')
            ->assertJsonMissingPath('data.faq.malicious')
            ->assertJsonMissingPath('data.totally_unknown_section');
    }
}
