<?php

namespace Tests\Feature\Pos;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\TenderType;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * S4-1 (16 Oct 2026): a till's write has no authenticated user, so the
 * Order's Auditable fallback stamped it "Customer" — the diner's role on a
 * sale a cashier rang up. The row must name the terminal, and the cashier
 * when the payload named one.
 */
class PosAuditActorTest extends PosTestCase
{
    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();

        $this->dir = storage_path('framework/testing/pos-audit-'.uniqid());

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

    /** @return list<array<string,mixed>> */
    private function events(): array
    {
        $file = $this->dir.'/activity-'.now()->format('Y-m-d').'.log';

        if (! file_exists($file)) {
            return [];
        }

        return array_map(
            fn ($l) => json_decode($l, true),
            array_values(array_filter(explode("\n", file_get_contents($file))))
        );
    }

    /** @return array<string,mixed> */
    private function sale(array $overrides = []): array
    {
        $category = Category::factory()->create(['restaurant_id' => $this->restaurant->id]);
        $burger = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'price' => 100.00,
            'discounted_price' => null,
        ]);
        $cash = new TenderType(['name' => 'Cash', 'kind' => 'cash']);
        $cash->restaurant_id = $this->restaurant->id;
        $cash->save();

        return array_merge([
            'client_transaction_id' => (string) Str::uuid(),
            'branch_id' => $this->branch->id,
            'order_type' => 'takeaway',
            'created_at' => '2026-10-16T08:00:00+02:00',
            'lines' => [['menu_item_id' => $burger->id, 'quantity' => 1, 'name_snapshot' => 'Classic Burger']],
            'payments' => [['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $cash->id, 'amount_minor' => 10000]],
        ], $overrides);
    }

    public function test_a_pos_sale_is_audited_as_the_terminal_and_the_cashier_not_as_a_customer(): void
    {
        $token = $this->claimTerminal()['token'];

        $orderId = $this->postJson('/api/pos/orders', $this->sale(['acting_user_id' => $this->owner->id]), $this->deviceHeaders($token))
            ->assertCreated()->json('data.id');

        $event = collect($this->events())
            ->first(fn ($e) => $e['action'] === 'order.created' && $e['subject_id'] === $orderId);

        $this->assertNotNull($event, 'the order.created row was written');
        $this->assertSame('TERMINAL', $event['actor_role']);
        $this->assertSame('Till 1 · '.$this->owner->name, $event['actor_name']);
        $this->assertSame($this->owner->id, $event['actor_id']);
        $this->assertSame($this->restaurant->id, $event['tenant_id']);
        $this->assertStringNotContainsString('Customer', (string) $event['actor_name']);

        // Every row the trait writes in the same request reads the same way —
        // the order's move to COMPLETED once its payments landed included.
        $others = collect($this->events())
            ->where('subject_id', $orderId)
            ->filter(fn ($e) => str_starts_with($e['action'], 'order.'));
        $this->assertGreaterThan(1, $others->count());
        $this->assertSame(['TERMINAL'], $others->pluck('actor_role')->unique()->values()->all());

        // The service's own hand-written row names the cashier it verified.
        $explicit = collect($this->events())->firstWhere('action', 'pos_order.created');
        $this->assertSame($this->owner->name, $explicit['actor_name']);
    }

    public function test_a_sale_with_no_named_cashier_is_audited_as_the_terminal_alone(): void
    {
        $token = $this->claimTerminal()['token'];

        $orderId = $this->postJson('/api/pos/orders', $this->sale(), $this->deviceHeaders($token))
            ->assertCreated()->json('data.id');

        $event = collect($this->events())
            ->first(fn ($e) => $e['action'] === 'order.created' && $e['subject_id'] === $orderId);

        $this->assertNotNull($event);
        $this->assertSame('TERMINAL', $event['actor_role']);
        $this->assertSame('Till 1', $event['actor_name']);
        $this->assertNull($event['actor_id']);

        // The service's hand-stamped TERMINAL row used to carry no name at all.
        $explicit = collect($this->events())->firstWhere('action', 'pos_order.created');
        $this->assertSame('TERMINAL', $explicit['actor_role']);
        $this->assertSame('Till 1', $explicit['actor_name']);
    }
}
