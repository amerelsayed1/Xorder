<?php

namespace Tests\Feature;

use App\Enums\InvoiceVoidReason;
use App\Enums\PurchaseCloseReason;
use App\Enums\PurchaseStatus;
use App\Enums\SubscriptionStatus;
use App\Enums\TenantCapability;
use App\Exceptions\PurchasingRefusal;
use App\Models\Branch;
use App\Models\PurchaseOrder;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\StockItem;
use App\Models\StockLevel;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Models\SupplierInvoice;
use App\Models\SupplierPayment;
use App\Models\SupplierPaymentAllocation;
use App\Models\User;
use App\Services\PurchaseOrderService;
use App\Services\SupplierLedgerService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * CB-09 slice c: supplier invoices, supplier payments and their allocations,
 * derived supplier balances, and closing a part delivery short (D11).
 *
 * The default business here has `purchasing` and deliberately NOT `pos`
 * (owner decision 2026-09-12: purchasing is standalone). Only the drawer-link
 * test adds `pos`, because only a till produces pay-outs.
 *
 * SQLite runs these, where lockForUpdate is a no-op. What is proved here is
 * every RULE, including under a stale read (a page or model loaded before
 * another write, then acted on), which is exactly what the lock-and-re-read
 * defends. The row lock itself was proved by hand on PostgreSQL with
 * concurrent processes (design §15).
 */
class PurchasingInvoicesAndPaymentsTest extends TestCase
{
    use RefreshDatabase;

    private string $activityDir;

    protected function setUp(): void
    {
        parent::setUp();

        $this->activityDir = storage_path('framework/testing/audit-'.uniqid());
        config([
            'platform.activity_log_file' => true,
            'logging.channels.activity.path' => $this->activityDir.'/activity.log',
        ]);
        Log::forgetChannel('activity');
    }

    protected function tearDown(): void
    {
        Log::forgetChannel('activity');
        File::deleteDirectory($this->activityDir);

        parent::tearDown();
    }

    private function event(string $action, int $restaurantId): ?array
    {
        $file = $this->activityDir.'/activity-'.now()->format('Y-m-d').'.log';
        $events = file_exists($file)
            ? array_map(fn ($l) => json_decode($l, true), array_values(array_filter(explode("\n", file_get_contents($file)))))
            : [];

        return collect($events)->first(fn (array $e) => ($e['action'] ?? null) === $action && ($e['tenant_id'] ?? null) === $restaurantId);
    }

    // ------------------------------------------------------------- fixtures

    private function tenant(array $features = ['purchasing'], array $attributes = []): Restaurant
    {
        $restaurant = Restaurant::factory()->create($attributes);
        foreach ($features as $key) {
            $restaurant->features()->create(['feature_key' => $key, 'is_enabled' => true]);
        }

        return $restaurant;
    }

    private function owner(Restaurant $restaurant): User
    {
        return User::factory()->restaurantAdmin($restaurant->id)->create();
    }

    private function staffWith(Restaurant $restaurant, array $capabilities): User
    {
        $role = new Role(['name' => 'Role '.uniqid()]);
        $role->forceFill([
            'restaurant_id' => $restaurant->id,
            'capabilities' => TenantCapability::expand($capabilities),
            'is_system' => false,
        ])->save();

        return User::factory()->staff($restaurant->id, $role->id)->create();
    }

    private function branch(Restaurant $restaurant, string $name = 'Downtown'): Branch
    {
        $branch = new Branch(['name_en' => $name]);
        $branch->restaurant_id = $restaurant->id;
        $branch->save();

        return $branch;
    }

    private function supplier(Restaurant $restaurant, array $attributes = []): Supplier
    {
        $supplier = new Supplier(array_merge(['name_en' => 'Delta Dairy'], $attributes));
        $supplier->restaurant_id = $restaurant->id;
        $supplier->save();

        return $supplier;
    }

    private function stockItem(Restaurant $restaurant): StockItem
    {
        $item = new StockItem(['name_en' => 'Milk 1L', 'unit_code' => 'ea']);
        $item->restaurant_id = $restaurant->id;
        $item->save();

        return $item;
    }

    /** A business with purchasing and no pos: [restaurant, owner, branch, supplier]. */
    private function scene(): array
    {
        $restaurant = $this->tenant();

        return [$restaurant, $this->owner($restaurant), $this->branch($restaurant), $this->supplier($restaurant)];
    }

    private function invoiceBody(Branch $branch, Supplier $supplier, array $extra = []): array
    {
        return array_merge([
            'branch_id' => $branch->id,
            'supplier_id' => $supplier->id,
            'number' => 'INV-'.Str::random(6),
            'issued_at' => '2026-03-01',
            'total_minor' => 100000,
            'tax_minor' => 12281,
        ], $extra);
    }

    private function invoice(User $as, Branch $branch, Supplier $supplier, array $extra = []): array
    {
        return $this->actingAs($as)->postJson('/api/dashboard/supplier-invoices', $this->invoiceBody($branch, $supplier, $extra))
            ->assertCreated()->json('data');
    }

    /** @param list<array{0:int,1:int}> $allocations [invoice id, amount] */
    private function payBody(Branch $branch, Supplier $supplier, int $amount, array $allocations = [], array $extra = []): array
    {
        return array_merge([
            'branch_id' => $branch->id,
            'supplier_id' => $supplier->id,
            'method' => 'bank_transfer',
            'amount_minor' => $amount,
            'paid_at' => '2026-03-05',
            'allocations' => array_map(fn ($a) => ['supplier_invoice_id' => $a[0], 'amount_minor' => $a[1]], $allocations),
        ], $extra);
    }

    private function pay(User $as, Branch $branch, Supplier $supplier, int $amount, array $allocations = [], array $extra = [])
    {
        return $this->actingAs($as)->postJson('/api/dashboard/supplier-payments', $this->payBody($branch, $supplier, $amount, $allocations, $extra));
    }

    private function getInvoice(User $as, int $id): array
    {
        return $this->actingAs($as)->getJson("/api/dashboard/supplier-invoices/{$id}")->assertOk()->json('data');
    }

    private function sentOrder(User $as, Branch $branch, Supplier $supplier, array $lines): array
    {
        $draft = $this->actingAs($as)->postJson('/api/dashboard/purchase-orders', [
            'branch_id' => $branch->id, 'supplier_id' => $supplier->id, 'lines' => $lines,
        ])->assertCreated()->json('data');

        return $this->actingAs($as)->postJson("/api/dashboard/purchase-orders/{$draft['id']}/send")->assertOk()->json('data');
    }

    private function receive(User $as, array $order, array $byIndex)
    {
        $lines = [];
        foreach ($byIndex as $i => $milli) {
            $lines[] = ['line_id' => $order['lines'][$i]['id'], 'quantity_milli' => $milli];
        }

        return $this->actingAs($as)->postJson("/api/dashboard/purchase-orders/{$order['id']}/receipts", ['lines' => $lines]);
    }

    /** A synced till pay-out (POS-BE-009 row), as the till would have written it. */
    private function payout(Restaurant $restaurant, Branch $branch, int $amount, string $direction = 'out'): int
    {
        $terminal = DB::table('pos_terminals')->insertGetId([
            'restaurant_id' => $restaurant->id, 'branch_id' => $branch->id, 'terminal_id' => (string) Str::uuid(),
            'name' => 'Till 1', 'created_at' => now(), 'updated_at' => now(),
        ]);
        $shift = DB::table('pos_shifts')->insertGetId([
            'restaurant_id' => $restaurant->id, 'branch_id' => $branch->id, 'pos_terminal_id' => $terminal,
            'client_transaction_id' => (string) Str::uuid(), 'opened_at' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        return DB::table('pos_cash_movements')->insertGetId([
            'restaurant_id' => $restaurant->id, 'branch_id' => $branch->id, 'pos_shift_id' => $shift,
            'pos_terminal_id' => $terminal, 'client_transaction_id' => (string) Str::uuid(), 'direction' => $direction,
            'amount_minor' => $amount, 'reason' => 'Paid the dairy', 'occurred_at' => now(),
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function allocatedTo(int $invoiceId): int
    {
        return (int) SupplierPaymentAllocation::withoutGlobalScopes()
            ->join('supplier_payments', 'supplier_payments.id', '=', 'supplier_payment_allocations.supplier_payment_id')
            ->where('supplier_payment_allocations.supplier_invoice_id', $invoiceId)
            ->whereNull('supplier_payments.voided_at')
            ->sum('supplier_payment_allocations.amount_minor');
    }

    // ----------------------------------------------------------- gate stack

    public function test_feature_off_blocks_every_slice_c_route_even_for_the_owner(): void
    {
        $restaurant = $this->tenant(['pos']);
        $owner = $this->owner($restaurant);
        $supplier = $this->supplier($restaurant);

        foreach (['supplier-invoices', 'supplier-payments', 'suppliers/balances', "suppliers/{$supplier->id}/account", 'purchasing/drawer-payouts'] as $path) {
            $this->actingAs($owner)->getJson("/api/dashboard/{$path}")->assertForbidden();
        }
        $this->actingAs($owner)->postJson('/api/dashboard/supplier-invoices', [])->assertForbidden();
        $this->actingAs($owner)->postJson('/api/dashboard/supplier-payments', [])->assertForbidden();
        $this->assertSame(0, SupplierInvoice::withoutGlobalScopes()->count());
    }

    public function test_staff_without_purchase_manage_is_refused_reads_and_writes(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $invoice = $this->invoice($owner, $branch, $supplier);
        $payment = $this->pay($owner, $branch, $supplier, 1000, [[$invoice['id'], 1000]])->assertCreated()->json('data');
        $clerk = $this->staffWith($restaurant, ['menu.view', 'branches.view', 'settings.view', 'settings.update']);

        foreach (['supplier-invoices', "supplier-invoices/{$invoice['id']}", 'supplier-payments', "supplier-payments/{$payment['id']}",
            'suppliers/balances', "suppliers/{$supplier->id}/account", 'purchasing/drawer-payouts'] as $path) {
            $this->actingAs($clerk)->getJson("/api/dashboard/{$path}")->assertForbidden();
        }
        $this->actingAs($clerk)->postJson('/api/dashboard/supplier-invoices', $this->invoiceBody($branch, $supplier))->assertForbidden();
        $this->actingAs($clerk)->postJson("/api/dashboard/supplier-payments/{$payment['id']}/void", ['reason' => 'wrong_amount'])->assertForbidden();
        $this->actingAs($clerk)->postJson("/api/dashboard/supplier-invoices/{$invoice['id']}/void", ['reason' => 'entered_twice'])->assertForbidden();
        $this->assertNull(SupplierPayment::withoutGlobalScopes()->find($payment['id'])->voided_at);
    }

    public function test_a_buyer_with_only_purchase_manage_runs_the_ledger_on_a_business_with_no_pos(): void
    {
        $restaurant = $this->tenant(['purchasing']);
        $this->assertFalse($restaurant->hasFeature('pos'));
        $buyer = $this->staffWith($restaurant, ['purchase.manage']);
        $branch = $this->branch($restaurant);
        $supplier = $this->supplier($restaurant, ['payment_term_days' => 30]);

        $this->actingAs($buyer)->getJson('/api/dashboard/purchasing/lookups')->assertOk()
            ->assertJsonPath('data.suppliers.0.payment_term_days', 30);

        $invoice = $this->invoice($buyer, $branch, $supplier, ['total_minor' => 50000, 'tax_minor' => 0]);
        $this->pay($buyer, $branch, $supplier, 20000, [[$invoice['id'], 20000]])->assertCreated()
            ->assertJsonPath('data.allocated_minor', 20000)->assertJsonPath('data.on_account_minor', 0);

        $this->actingAs($buyer)->getJson("/api/dashboard/suppliers/{$supplier->id}/account?as_of=2026-03-15")->assertOk()
            ->assertJsonPath('data.figures.outstanding_minor', 30000);
        // No till, so no pay-outs to link, and nothing breaks.
        $this->actingAs($buyer)->getJson('/api/dashboard/purchasing/drawer-payouts')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_a_lapsed_subscription_blocks_writes_but_not_reads(): void
    {
        $restaurant = $this->tenant(['purchasing'], ['subscription_status' => SubscriptionStatus::EXPIRED]);
        $owner = $this->owner($restaurant);
        $branch = $this->branch($restaurant);
        $supplier = $this->supplier($restaurant);
        $invoice = app(SupplierLedgerService::class)->createInvoice($this->invoiceBody($branch, $supplier), $owner);
        $this->actingAs($owner);
        $order = app(PurchaseOrderService::class)->create(['branch_id' => $branch->id, 'supplier_id' => $supplier->id, 'lines' => [
            ['description' => 'Milk', 'unit_code' => 'ea', 'quantity_milli' => 1000, 'unit_cost_minor' => 100],
        ]], $owner);

        foreach (['supplier-invoices', "supplier-invoices/{$invoice->id}", 'supplier-payments', 'suppliers/balances', "suppliers/{$supplier->id}/account"] as $path) {
            $this->actingAs($owner)->getJson("/api/dashboard/{$path}")->assertOk();
        }
        foreach ([
            ['post', '/api/dashboard/supplier-invoices', $this->invoiceBody($branch, $supplier)],
            ['put', "/api/dashboard/supplier-invoices/{$invoice->id}", $this->invoiceBody($branch, $supplier)],
            ['post', "/api/dashboard/supplier-invoices/{$invoice->id}/void", ['reason' => 'entered_twice']],
            ['post', '/api/dashboard/supplier-payments', $this->payBody($branch, $supplier, 100)],
            ['post', "/api/dashboard/purchase-orders/{$order->id}/close", ['reason' => 'no_longer_needed']],
        ] as [$verb, $url, $body]) {
            $this->actingAs($owner)->{$verb.'Json'}($url, $body)->assertForbidden()->assertJsonPath('code', 'subscription_inactive');
        }
        $this->assertNull($invoice->fresh()->voided_at);
    }

    // ------------------------------------------------------ tenant isolation

    public function test_another_businesss_invoices_payments_and_account_are_404(): void
    {
        [, $owner] = $this->scene();
        [, $theirOwner, $theirBranch, $theirSupplier] = $this->scene();
        $invoice = $this->invoice($theirOwner, $theirBranch, $theirSupplier);
        $payment = $this->pay($theirOwner, $theirBranch, $theirSupplier, 500)->assertCreated()->json('data');

        $this->actingAs($owner)->getJson("/api/dashboard/supplier-invoices/{$invoice['id']}")->assertNotFound();
        $this->actingAs($owner)->getJson("/api/dashboard/supplier-payments/{$payment['id']}")->assertNotFound();
        $this->actingAs($owner)->getJson("/api/dashboard/suppliers/{$theirSupplier->id}/account")->assertNotFound();
        $this->actingAs($owner)->putJson("/api/dashboard/supplier-invoices/{$invoice['id']}", ['number' => 'X'])->assertNotFound();
        $this->actingAs($owner)->postJson("/api/dashboard/supplier-invoices/{$invoice['id']}/void", ['reason' => 'entered_twice'])->assertNotFound();
        $this->actingAs($owner)->postJson("/api/dashboard/supplier-payments/{$payment['id']}/void", ['reason' => 'wrong_amount'])->assertNotFound();

        // Their rows never show up in our lists or balances.
        $this->actingAs($owner)->getJson('/api/dashboard/supplier-invoices')->assertOk()->assertJsonCount(0, 'data');
        $this->actingAs($owner)->getJson('/api/dashboard/supplier-payments')->assertOk()->assertJsonCount(0, 'data');
        $this->actingAs($owner)->getJson('/api/dashboard/suppliers/balances')->assertOk()->assertJsonCount(0, 'data');
        $this->assertNull(SupplierInvoice::withoutGlobalScopes()->find($invoice['id'])->voided_at);
    }

    public function test_foreign_ids_in_the_body_are_422_and_restaurant_id_is_ignored(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        [$theirs, $theirOwner, $theirBranch, $theirSupplier] = $this->scene();
        $theirInvoice = $this->invoice($theirOwner, $theirBranch, $theirSupplier);
        $theirOrder = $this->sentOrder($theirOwner, $theirBranch, $theirSupplier, [['description' => 'Milk', 'unit_code' => 'ea', 'quantity_milli' => 1000, 'unit_cost_minor' => 100]]);
        $theirPayout = $this->payout($theirs, $theirBranch, 500);

        $this->actingAs($owner)->postJson('/api/dashboard/supplier-invoices', $this->invoiceBody($theirBranch, $theirSupplier, ['purchase_order_id' => $theirOrder['id']]))
            ->assertStatus(422)->assertJsonValidationErrors(['branch_id', 'supplier_id', 'purchase_order_id']);
        $this->pay($owner, $branch, $supplier, 500, [[$theirInvoice['id'], 500]], ['method' => 'cash', 'pos_cash_movement_id' => $theirPayout])
            ->assertStatus(422)->assertJsonValidationErrors(['allocations.0.supplier_invoice_id', 'pos_cash_movement_id']);

        $mine = $this->actingAs($owner)->postJson('/api/dashboard/supplier-invoices', $this->invoiceBody($branch, $supplier, ['restaurant_id' => $theirs->id]))
            ->assertCreated()->json('data');
        $this->assertSame($restaurant->id, SupplierInvoice::withoutGlobalScopes()->find($mine['id'])->restaurant_id);
        $this->assertSame(0, $this->allocatedTo($theirInvoice['id']));
    }

    // -------------------------------------------------------------- invoices

    public function test_an_invoice_typed_off_the_paper(): void
    {
        [, $owner, $branch] = $this->scene();
        $supplier = $this->supplier($owner->restaurant, ['name_en' => 'Terms 30', 'payment_term_days' => 30]);

        // A gross total and the rate inside it: 1,140.00 at 14% holds 140.00.
        $bill = $this->invoice($owner, $branch, $supplier, ['total_minor' => 114000, 'tax_minor' => null, 'tax_rate_bp' => 1400]);
        $this->assertSame(14000, $bill['tax_minor']);
        $this->assertSame(100000, $bill['subtotal_minor']);
        // The due date the terms imply, from the paper's date, stored.
        $this->assertSame('2026-03-31', $bill['due_at']);
        // Due on 31 March and unpaid, so late as at the business's own today.
        $this->assertSame('overdue', $bill['state']);
        $this->assertGreaterThan(0, $bill['days_late']);
        $this->assertSame([], $bill['lines'], 'typed off the paper: no lines, as on the till');

        $body = fn (array $extra) => $this->invoiceBody($branch, $supplier, $extra);
        $this->actingAs($owner)->postJson('/api/dashboard/supplier-invoices', $body(['due_at' => '2026-02-01']))->assertStatus(422)->assertJsonValidationErrors('due_at');
        $this->actingAs($owner)->postJson('/api/dashboard/supplier-invoices', $body(['total_minor' => 1000, 'tax_minor' => 1001]))->assertStatus(422)->assertJsonValidationErrors('tax_minor');
        $this->actingAs($owner)->postJson('/api/dashboard/supplier-invoices', $body(['total_minor' => 0, 'tax_minor' => 0]))->assertStatus(422)->assertJsonValidationErrors('total_minor');
        $this->actingAs($owner)->postJson('/api/dashboard/supplier-invoices', $body(['total_minor' => null]))->assertStatus(422)->assertJsonValidationErrors('total_minor');
        $this->actingAs($owner)->postJson('/api/dashboard/supplier-invoices', $body(['number' => '   ']))->assertStatus(422)->assertJsonValidationErrors('number');
        $this->actingAs($owner)->postJson('/api/dashboard/supplier-invoices', $body(['issued_at' => now()->addDays(5)->toDateString()]))->assertStatus(422)->assertJsonValidationErrors('issued_at');
        $this->assertSame(1, SupplierInvoice::withoutGlobalScopes()->count());
    }

    public function test_invoice_lines_are_totalled_by_the_server_with_tax_per_rate(): void
    {
        [, $owner, $branch, $supplier] = $this->scene();

        // purchase_order_test.dart: three lines of 33.33 at 14% are 14.00 of
        // tax, not 14.01. A typed total is ignored when there are lines.
        $bill = $this->invoice($owner, $branch, $supplier, [
            'total_minor' => 1, 'tax_minor' => 0,
            'lines' => array_fill(0, 3, ['description' => 'Cheese 1kg', 'quantity_milli' => 1000, 'unit_cost_minor' => 3333, 'tax_rate_bp' => 1400]),
        ]);

        $this->assertSame(11399, $bill['total_minor']);
        $this->assertSame(1400, $bill['tax_minor']);
        $this->assertSame(9999, $bill['subtotal_minor']);
        $this->assertCount(3, $bill['lines']);
        $this->assertSame(3333, $bill['lines'][0]['line_total_minor']);

        // 12.5 kg at 47.30 is 591.25, and 14% of it 82.78.
        $kg = $this->invoice($owner, $branch, $supplier, ['lines' => [
            ['description' => 'Chicken', 'quantity_milli' => 12500, 'unit_cost_minor' => 4730, 'tax_rate_bp' => 1400],
        ]]);
        $this->assertSame(59125 + 8278, $kg['total_minor']);
    }

    public function test_a_live_number_is_unique_per_supplier_and_a_voided_one_can_be_entered_again(): void
    {
        [, $owner, $branch, $supplier] = $this->scene();
        $other = $this->supplier($owner->restaurant, ['name_en' => 'Other']);
        $first = $this->invoice($owner, $branch, $supplier, ['number' => 'INV-900']);

        $this->actingAs($owner)->postJson('/api/dashboard/supplier-invoices', $this->invoiceBody($branch, $supplier, ['number' => ' inv-900 ']))
            ->assertStatus(422)->assertJsonPath('code', 'INVOICE_NUMBER_TAKEN')->assertJsonValidationErrors('number');
        // Another supplier's numbering is its own.
        $this->invoice($owner, $branch, $other, ['number' => 'INV-900']);

        $this->actingAs($owner)->postJson("/api/dashboard/supplier-invoices/{$first['id']}/void", ['reason' => 'entered_twice'])->assertOk();
        $again = $this->invoice($owner, $branch, $supplier, ['number' => 'INV-900']);
        $this->assertNotSame($first['id'], $again['id']);

        // The unique index is the backstop behind the pre-check.
        $this->assertNull(SupplierInvoice::withoutGlobalScopes()->find($first['id'])->active_number_key);
        $this->assertSame('inv-900', SupplierInvoice::withoutGlobalScopes()->find($again['id'])->active_number_key);
    }

    public function test_an_invoice_is_editable_only_while_live_and_unpaid(): void
    {
        [, $owner, $branch, $supplier] = $this->scene();
        $bill = $this->invoice($owner, $branch, $supplier, ['number' => 'A-1']);
        $url = "/api/dashboard/supplier-invoices/{$bill['id']}";

        $this->actingAs($owner)->putJson($url, $this->invoiceBody($branch, $supplier, ['number' => 'A-1', 'total_minor' => 90000, 'tax_minor' => 0]))
            ->assertOk()->assertJsonPath('data.total_minor', 90000)->assertJsonPath('data.can_edit', true);

        $payment = $this->pay($owner, $branch, $supplier, 1000, [[$bill['id'], 1000]])->assertCreated()->json('data');
        $this->assertFalse($this->getInvoice($owner, $bill['id'])['can_edit']);
        $this->actingAs($owner)->putJson($url, $this->invoiceBody($branch, $supplier, ['number' => 'A-1', 'total_minor' => 500, 'tax_minor' => 0]))
            ->assertStatus(409)->assertJsonPath('code', 'INVOICE_HAS_PAYMENTS');
        $this->assertSame(90000, SupplierInvoice::withoutGlobalScopes()->find($bill['id'])->total_minor);

        $this->actingAs($owner)->postJson("/api/dashboard/supplier-payments/{$payment['id']}/void", ['reason' => 'wrong_invoice'])->assertOk();
        $this->actingAs($owner)->putJson($url, $this->invoiceBody($branch, $supplier, ['number' => 'A-1', 'total_minor' => 500, 'tax_minor' => 0]))->assertOk();

        $this->actingAs($owner)->postJson("{$url}/void", ['reason' => 'wrong_amount'])->assertOk();
        $this->actingAs($owner)->putJson($url, $this->invoiceBody($branch, $supplier, ['number' => 'A-1']))
            ->assertStatus(409)->assertJsonPath('code', 'INVOICE_VOIDED');
    }

    public function test_an_invoice_with_live_payments_cannot_be_voided_and_a_void_needs_a_reason(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $bill = $this->invoice($owner, $branch, $supplier);
        $url = "/api/dashboard/supplier-invoices/{$bill['id']}/void";
        $payment = $this->pay($owner, $branch, $supplier, 40000, [[$bill['id'], 40000]])->assertCreated()->json('data');

        $this->actingAs($owner)->postJson($url, ['reason' => 'entered_twice'])
            ->assertStatus(409)->assertJsonPath('code', 'INVOICE_HAS_PAYMENTS')->assertJsonPath('details.paid_minor', 40000);
        $this->actingAs($owner)->postJson($url, ['reason' => 'because'])->assertStatus(422)->assertJsonValidationErrors('reason');
        $this->actingAs($owner)->postJson($url, ['reason' => 'other'])->assertStatus(422)->assertJsonValidationErrors('note');

        $this->actingAs($owner)->postJson("/api/dashboard/supplier-payments/{$payment['id']}/void", ['reason' => 'wrong_amount'])->assertOk();
        $this->actingAs($owner)->postJson($url, ['reason' => 'other', 'note' => 'Supplier sent a corrected copy'])->assertOk()
            ->assertJsonPath('data.state', 'voided')->assertJsonPath('data.void_reason', 'other')->assertJsonPath('data.can_void', false);
        $this->actingAs($owner)->postJson($url, ['reason' => 'entered_twice'])->assertStatus(409)->assertJsonPath('code', 'INVOICE_ALREADY_VOIDED');

        // Nothing can be paid on a voided invoice, and it is still on record.
        $this->pay($owner, $branch, $supplier, 100, [[$bill['id'], 100]])->assertStatus(409)->assertJsonPath('code', 'PAYMENT_INVOICE_VOIDED');
        $this->actingAs($owner)->getJson('/api/dashboard/supplier-invoices?state=voided')->assertOk()->assertJsonCount(1, 'data');
        $this->assertNotNull($this->event('supplier_invoice.voided', $restaurant->id));
    }

    public function test_an_invoice_linked_to_an_order_shows_the_delivery_beside_it_and_never_reprices_stock(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $item = $this->stockItem($restaurant);

        // supplier_invoice_test.dart: ten at 100.00 plus 14%, eight arrived.
        $order = $this->sentOrder($owner, $branch, $supplier, [['stock_item_id' => $item->id, 'quantity_milli' => 10000, 'unit_cost_minor' => 10000, 'tax_rate_bp' => 1400]]);
        $this->receive($owner, $order, [0 => 8000])->assertOk();
        $this->actingAs($owner)->getJson("/api/dashboard/purchase-orders/{$order['id']}")->assertJsonPath('data.received_total_minor', 91200);

        $level = fn () => StockLevel::withoutGlobalScopes()->where('stock_item_id', $item->id)->first()->only(['quantity_milli', 'average_cost_minor']);
        $before = [$level(), StockMovement::withoutGlobalScopes()->count()];

        // Billed for all ten at a higher price than ordered.
        $bill = $this->invoice($owner, $branch, $supplier, ['purchase_order_id' => $order['id'], 'total_minor' => 125400, 'tax_minor' => 15400]);
        $this->assertSame($order['reference'], $bill['purchase_order_reference']);
        $this->assertSame(80000, $bill['purchase_order']['received_value_minor']);
        $this->assertSame(91200, $bill['purchase_order']['received_total_minor']);
        $this->assertSame(125400 - 91200, $bill['purchase_order']['variance_minor']);

        $this->actingAs($owner)->putJson("/api/dashboard/supplier-invoices/{$bill['id']}", $this->invoiceBody($branch, $supplier, [
            'number' => $bill['number'], 'purchase_order_id' => $order['id'], 'total_minor' => 91200, 'tax_minor' => 11200,
        ]))->assertOk()->assertJsonPath('data.purchase_order.variance_minor', 0);

        $this->assertSame($before, [$level(), StockMovement::withoutGlobalScopes()->count()], 'an invoice never reprices or moves stock');
        $this->assertSame(['quantity_milli' => 8000, 'average_cost_minor' => 10000], $level());
    }

    public function test_a_linked_order_must_be_the_suppliers_the_branchs_and_sent(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $other = $this->supplier($restaurant, ['name_en' => 'Other']);
        $uptown = $this->branch($restaurant, 'Uptown');
        $line = [['description' => 'Milk', 'unit_code' => 'ea', 'quantity_milli' => 1000, 'unit_cost_minor' => 100]];
        $theirs = $this->sentOrder($owner, $branch, $other, $line);
        $elsewhere = $this->sentOrder($owner, $uptown, $supplier, $line);
        $draft = $this->actingAs($owner)->postJson('/api/dashboard/purchase-orders', ['branch_id' => $branch->id, 'supplier_id' => $supplier->id, 'lines' => $line])->json('data');

        foreach ([[$theirs, 'INVOICE_PO_OTHER_SUPPLIER'], [$elsewhere, 'INVOICE_PO_OTHER_BRANCH'], [$draft, 'INVOICE_PO_DRAFT']] as [$order, $code]) {
            $this->actingAs($owner)->postJson('/api/dashboard/supplier-invoices', $this->invoiceBody($branch, $supplier, ['purchase_order_id' => $order['id']]))
                ->assertStatus(422)->assertJsonPath('code', $code)->assertJsonValidationErrors('purchase_order_id');
        }
        $this->assertSame(0, SupplierInvoice::withoutGlobalScopes()->count());
    }

    // -------------------------------------------------------------- payments

    public function test_a_payment_is_allocated_across_invoices_and_the_rest_is_on_account(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $a = $this->invoice($owner, $branch, $supplier, ['total_minor' => 100000, 'tax_minor' => 0]);
        $b = $this->invoice($owner, $branch, $supplier, ['total_minor' => 50000, 'tax_minor' => 0]);

        $payment = $this->pay($owner, $branch, $supplier, 200000, [[$a['id'], 100000], [$b['id'], 30000]])
            ->assertCreated()->assertJsonPath('data.allocated_minor', 130000)->assertJsonPath('data.on_account_minor', 70000)
            ->assertJsonCount(2, 'data.allocations')->json('data');

        $this->assertSame('settled', $this->getInvoice($owner, $a['id'])['state']);
        $this->assertSame(20000, $this->getInvoice($owner, $b['id'])['outstanding_minor']);
        $this->assertSame(30000, $this->getInvoice($owner, $b['id'])['paid_minor']);
        $this->actingAs($owner)->getJson('/api/dashboard/supplier-invoices?state=settled')->assertJsonCount(1, 'data');
        $this->actingAs($owner)->getJson('/api/dashboard/supplier-invoices?state=open')->assertJsonCount(1, 'data');
        $this->assertNotNull($this->event('supplier_payment.recorded', $restaurant->id));

        // All of it on account: no allocation at all.
        $this->pay($owner, $branch, $supplier, 5000)->assertCreated()->assertJsonPath('data.on_account_minor', 5000);
        $this->assertSame(1, SupplierPayment::withoutGlobalScopes()->whereKey($payment['id'])->count());
    }

    public function test_allocations_can_never_exceed_an_invoice_total_or_the_payment(): void
    {
        [, $owner, $branch, $supplier] = $this->scene();
        $bill = $this->invoice($owner, $branch, $supplier, ['total_minor' => 100000, 'tax_minor' => 0]);

        $this->pay($owner, $branch, $supplier, 60000, [[$bill['id'], 60000]])->assertCreated();

        $refused = $this->pay($owner, $branch, $supplier, 50000, [[$bill['id'], 50000]])
            ->assertStatus(409)->assertJsonPath('code', 'PAYMENT_EXCEEDS_INVOICE')
            ->assertJsonPath('details.room_minor', 40000)->assertJsonPath('details.paid_minor', 60000)
            ->assertJsonValidationErrors('allocations.0.amount_minor');
        $this->assertStringContainsString('400.00', $refused->json('message'), 'the refusal names the room left');

        $this->pay($owner, $branch, $supplier, 40000, [[$bill['id'], 40000]])->assertCreated();
        $this->pay($owner, $branch, $supplier, 1, [[$bill['id'], 1]])->assertStatus(409)->assertJsonPath('details.room_minor', 0);

        // The allocations can't add up to more than the payment either.
        $other = $this->invoice($owner, $branch, $supplier, ['total_minor' => 100000, 'tax_minor' => 0]);
        $this->pay($owner, $branch, $supplier, 1000, [[$other['id'], 1001]])
            ->assertStatus(422)->assertJsonPath('code', 'ALLOCATIONS_EXCEED_PAYMENT');
        $this->pay($owner, $branch, $supplier, 2000, [[$other['id'], 1000], [$other['id'], 1000]])
            ->assertStatus(422)->assertJsonValidationErrors('allocations.1.supplier_invoice_id');

        $this->assertSame(100000, $this->allocatedTo($bill['id']));
        $this->assertSame(0, $this->allocatedTo($other['id']));
        $this->assertSame(2, SupplierPayment::withoutGlobalScopes()->count(), 'a refused payment writes nothing');
    }

    /**
     * The concurrent case, by hand, as SQLite can show it: two bookkeepers
     * open the same invoice while it has 1,000.00 outstanding. The first pays
     * 700.00. The second, still looking at 1,000.00, pays 500.00. The service
     * must read what is allocated UNDER ITS LOCK, not trust the page, and
     * refuse with the real room (300.00). On PostgreSQL the same run with
     * truly concurrent processes was checked by hand (design §15).
     */
    public function test_a_stale_page_cannot_over_allocate_an_invoice(): void
    {
        [, $owner, $branch, $supplier] = $this->scene();
        $bill = $this->invoice($owner, $branch, $supplier, ['total_minor' => 100000, 'tax_minor' => 0]);

        $pageA = $this->getInvoice($owner, $bill['id']);
        $pageB = $this->getInvoice($owner, $bill['id']);
        $stale = SupplierInvoice::withoutGlobalScopes()->findOrFail($bill['id']);
        $this->assertSame(100000, $pageA['outstanding_minor']);
        $this->assertSame(100000, $pageB['outstanding_minor']);

        $this->pay($owner, $branch, $supplier, 70000, [[$pageA['id'], 70000]])->assertCreated();

        // B, from its stale page, over HTTP…
        $this->pay($owner, $branch, $supplier, 50000, [[$pageB['id'], 50000]])
            ->assertStatus(409)->assertJsonPath('code', 'PAYMENT_EXCEEDS_INVOICE')->assertJsonPath('details.room_minor', 30000);

        // …and straight into the service, with the stale model's own total in hand.
        try {
            app(SupplierLedgerService::class)->pay($this->payBody($branch, $supplier, $stale->total_minor - 70000 + 1, [[$stale->id, $stale->total_minor - 70000 + 1]]), $owner);
            $this->fail('An allocation above the room left must be refused.');
        } catch (PurchasingRefusal $e) {
            $this->assertSame('PAYMENT_EXCEEDS_INVOICE', $e->refusal);
            $this->assertSame(30000, $e->details['room_minor']);
        }
        $this->assertSame(70000, $this->allocatedTo($bill['id']));

        // And the other stale race: a void from a page that saw it unpaid.
        try {
            app(SupplierLedgerService::class)->voidInvoice($stale, InvoiceVoidReason::ENTERED_TWICE, null, $owner);
            $this->fail('Voiding an invoice with live payments must be refused.');
        } catch (PurchasingRefusal $e) {
            $this->assertSame('INVOICE_HAS_PAYMENTS', $e->refusal);
        }
        $this->assertNull($stale->fresh()->voided_at);
    }

    public function test_a_payment_must_match_the_invoices_supplier_branch_and_currency(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $other = $this->supplier($restaurant, ['name_en' => 'Other']);
        $uptown = $this->branch($restaurant, 'Uptown');
        $othersBill = $this->invoice($owner, $branch, $other);
        $uptownBill = $this->invoice($owner, $uptown, $supplier);
        $bill = $this->invoice($owner, $branch, $supplier);

        $this->pay($owner, $branch, $supplier, 100, [[$othersBill['id'], 100]])->assertStatus(422)->assertJsonPath('code', 'PAYMENT_OTHER_SUPPLIER');
        $this->pay($owner, $branch, $supplier, 100, [[$uptownBill['id'], 100]])->assertStatus(422)->assertJsonPath('code', 'PAYMENT_OTHER_BRANCH');

        // The business changed currency after the invoice was entered.
        $restaurant->update(['currency' => 'KWD']);
        $owner->refresh();
        $this->pay($owner, $branch, $supplier, 100, [[$bill['id'], 100]])->assertStatus(422)->assertJsonPath('code', 'CURRENCY_DIFFERS');

        $this->assertSame(0, SupplierPayment::withoutGlobalScopes()->count());
    }

    public function test_voiding_a_payment_gives_its_room_back_and_is_final(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $bill = $this->invoice($owner, $branch, $supplier, ['total_minor' => 100000, 'tax_minor' => 0]);
        $payment = $this->pay($owner, $branch, $supplier, 100000, [[$bill['id'], 100000]], ['method' => 'cheque', 'reference' => 'CHQ-771'])->json('data');
        $this->assertSame('settled', $this->getInvoice($owner, $bill['id'])['state']);

        $url = "/api/dashboard/supplier-payments/{$payment['id']}/void";
        $this->actingAs($owner)->postJson($url, ['reason' => 'other'])->assertStatus(422)->assertJsonValidationErrors('note');
        $this->actingAs($owner)->postJson($url, ['reason' => 'cheque_bounced'])->assertOk()
            ->assertJsonPath('data.is_voided', true)->assertJsonPath('data.void_reason', 'cheque_bounced');
        $this->actingAs($owner)->postJson($url, ['reason' => 'cheque_bounced'])->assertStatus(409)->assertJsonPath('code', 'PAYMENT_ALREADY_VOIDED');

        $again = $this->getInvoice($owner, $bill['id']);
        // Unpaid again, and its March due date has passed.
        $this->assertSame('overdue', $again['state']);
        $this->assertSame(100000, $again['outstanding_minor']);
        $this->pay($owner, $branch, $supplier, 100000, [[$bill['id'], 100000]])->assertCreated();
        $this->assertNotNull($this->event('supplier_payment.voided', $restaurant->id));
    }

    // -------------------------------------------------------------- balances

    public function test_the_supplier_balance_is_derived_and_reconciles_by_construction(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $uptown = $this->branch($restaurant, 'Uptown');

        $i1 = $this->invoice($owner, $branch, $supplier, ['total_minor' => 100000, 'tax_minor' => 0, 'issued_at' => '2026-03-01', 'due_at' => '2026-03-10']);
        $i2 = $this->invoice($owner, $branch, $supplier, ['total_minor' => 50000, 'tax_minor' => 0, 'issued_at' => '2026-03-02', 'due_at' => '2026-04-30']);
        $i3 = $this->invoice($owner, $branch, $supplier, ['total_minor' => 20000, 'tax_minor' => 0, 'issued_at' => '2026-03-03']);
        $this->actingAs($owner)->postJson("/api/dashboard/supplier-invoices/{$i3['id']}/void", ['reason' => 'entered_twice'])->assertOk();
        $this->invoice($owner, $uptown, $supplier, ['total_minor' => 7000, 'tax_minor' => 0]);

        $this->pay($owner, $branch, $supplier, 30000, [[$i1['id'], 30000]], ['paid_at' => '2026-03-04'])->assertCreated();
        $this->pay($owner, $branch, $supplier, 20000, [], ['paid_at' => '2026-03-05'])->assertCreated();
        $p3 = $this->pay($owner, $branch, $supplier, 10000, [[$i2['id'], 10000]], ['paid_at' => '2026-03-06'])->json('data');
        $this->actingAs($owner)->postJson("/api/dashboard/supplier-payments/{$p3['id']}/void", ['reason' => 'entered_twice'])->assertOk();

        $account = $this->actingAs($owner)->getJson("/api/dashboard/suppliers/{$supplier->id}/account?branch_id={$branch->id}&as_of=2026-03-20")
            ->assertOk()->json('data');
        $f = $account['figures'];

        $this->assertSame(150000, $f['invoiced_minor'], 'voids and the other branch are excluded');
        $this->assertSame(50000, $f['paid_minor']);
        $this->assertSame(100000, $f['outstanding_minor']);
        $this->assertSame(70000, $f['overdue_minor'], 'on-account money reduces the balance, not what is late');
        $this->assertSame(20000, $f['on_account_minor']);

        // Reconciles by construction, three ways.
        $rows = $account['statement'];
        $this->assertCount(4, $rows);
        $this->assertSame($f['outstanding_minor'], end($rows)['balance_minor']);
        $this->assertSame($f['outstanding_minor'], array_sum(array_column($rows, 'debit_minor')) - array_sum(array_column($rows, 'credit_minor')));
        $this->assertSame($f['outstanding_minor'], array_sum(array_column($account['open_invoices'], 'outstanding_minor')) - $f['on_account_minor']);
        $this->assertSame([70000, 50000], array_column($account['open_invoices'], 'outstanding_minor'));
        $this->assertSame([true, false], array_column($account['open_invoices'], 'is_overdue'));
        $this->assertSame(10, $account['open_invoices'][0]['days_late']);
        $this->assertCount(3, $account['payments'], 'voided payments are listed, flagged');
        $this->assertSame(1, $account['voided_invoices']);

        // Every branch together, and the list agrees with the account.
        $all = $this->actingAs($owner)->getJson("/api/dashboard/suppliers/{$supplier->id}/account?as_of=2026-03-20")->json('data.figures');
        $this->assertSame(107000, $all['outstanding_minor']);
        $row = $this->actingAs($owner)->getJson('/api/dashboard/suppliers/balances')->assertOk()->json('data.0');
        $this->assertSame($supplier->id, $row['supplier_id']);
        foreach (['invoiced_minor', 'paid_minor', 'outstanding_minor', 'on_account_minor'] as $key) {
            $this->assertSame($all[$key], $row[$key], $key);
        }
        $this->actingAs($owner)->getJson("/api/dashboard/suppliers/balances?branch_id={$branch->id}")->assertJsonPath('data.0.outstanding_minor', 100000);

        // Nothing stores any of it.
        foreach (['suppliers' => ['balance', 'balance_minor'], 'supplier_invoices' => ['balance_minor', 'paid_minor', 'outstanding_minor', 'subtotal_minor'], 'supplier_payments' => ['balance_minor', 'on_account_minor', 'allocated_minor']] as $table => $columns) {
            foreach ($columns as $column) {
                $this->assertFalse(Schema::hasColumn($table, $column), "{$table}.{$column} must not exist");
            }
        }
    }

    // ------------------------------------------------------------ the drawer

    public function test_a_payment_links_to_a_till_pay_out_only_under_the_tills_rules(): void
    {
        $restaurant = $this->tenant(['purchasing', 'pos']);
        $owner = $this->owner($restaurant);
        $branch = $this->branch($restaurant);
        $uptown = $this->branch($restaurant, 'Uptown');
        $supplier = $this->supplier($restaurant);
        $out = $this->payout($restaurant, $branch, 50000);
        $in = $this->payout($restaurant, $branch, 50000, 'in');
        $away = $this->payout($restaurant, $uptown, 50000);

        $this->actingAs($owner)->getJson("/api/dashboard/purchasing/drawer-payouts?branch_id={$branch->id}")->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $out);

        $cash = fn (int $movement, int $amount = 50000, string $method = 'cash') => $this->pay($owner, $branch, $supplier, $amount, [], ['method' => $method, 'pos_cash_movement_id' => $movement]);
        $cash($out, 50000, 'bank_transfer')->assertStatus(422)->assertJsonPath('code', 'DRAWER_NEEDS_CASH');
        $cash($in)->assertStatus(422)->assertJsonPath('code', 'DRAWER_NOT_PAY_OUT');
        $cash($away)->assertStatus(422)->assertJsonPath('code', 'DRAWER_OTHER_BRANCH');
        $cash($out, 40000)->assertStatus(422)->assertJsonPath('code', 'DRAWER_AMOUNT_DIFFERS');

        $linked = $cash($out)->assertCreated()->assertJsonPath('data.pos_cash_movement_id', $out)
            ->assertJsonPath('data.cash_movement.amount_minor', 50000)->json('data');
        $cash($out)->assertStatus(409)->assertJsonPath('code', 'DRAWER_ALREADY_LINKED');
        $this->actingAs($owner)->getJson('/api/dashboard/purchasing/drawer-payouts')->assertJsonMissing(['id' => $out]);

        // Void the payment: the pay-out is free for the corrected one, and
        // the voided row still says which drawer the money left.
        $this->actingAs($owner)->postJson("/api/dashboard/supplier-payments/{$linked['id']}/void", ['reason' => 'wrong_supplier'])->assertOk()
            ->assertJsonPath('data.pos_cash_movement_id', $out);
        $cash($out)->assertCreated();
    }

    // ----------------------------------------------------------- close short

    public function test_only_a_part_delivered_order_can_be_closed_short(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $item = $this->stockItem($restaurant);
        $line = [['stock_item_id' => $item->id, 'quantity_milli' => 10000, 'unit_cost_minor' => 1000]];
        $close = fn (array $o) => $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$o['id']}/close", ['reason' => 'supplier_cannot_supply']);

        $draft = $this->actingAs($owner)->postJson('/api/dashboard/purchase-orders', ['branch_id' => $branch->id, 'supplier_id' => $supplier->id, 'lines' => $line])->json('data');
        $close($draft)->assertStatus(409)->assertJsonPath('code', 'PO_CANNOT_CLOSE_SHORT');

        $sent = $this->sentOrder($owner, $branch, $supplier, $line);
        $this->assertFalse($sent['can_close_short']);
        $close($sent)->assertStatus(409)->assertJsonPath('code', 'PO_CANNOT_CLOSE_SHORT');

        $full = $this->sentOrder($owner, $branch, $supplier, $line);
        $this->receive($owner, $full, [0 => 10000])->assertJsonPath('data.status', 'received');
        $close($full)->assertStatus(409);

        $cancelled = $this->sentOrder($owner, $branch, $supplier, $line);
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$cancelled['id']}/cancel")->assertOk();
        $close($cancelled)->assertStatus(409);

        $partial = $this->sentOrder($owner, $branch, $supplier, $line);
        $this->receive($owner, $partial, [0 => 4000])->assertJsonPath('data.can_close_short', true);
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$partial['id']}/close", ['reason' => 'other'])
            ->assertStatus(422)->assertJsonValidationErrors('note');
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$partial['id']}/close", ['reason' => 'late'])
            ->assertStatus(422)->assertJsonValidationErrors('reason');
        $close($partial)->assertOk()->assertJsonPath('data.status', 'received')->assertJsonPath('data.closed_short', true);
        $close($partial)->assertStatus(409)->assertJsonPath('code', 'PO_CANNOT_CLOSE_SHORT');

        $clerk = $this->staffWith($restaurant, ['menu.view']);
        $this->actingAs($clerk)->postJson("/api/dashboard/purchase-orders/{$partial['id']}/close", ['reason' => 'no_longer_needed'])->assertForbidden();
    }

    public function test_closing_short_records_what_is_not_coming_and_never_touches_stock(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $item = $this->stockItem($restaurant);
        $order = $this->sentOrder($owner, $branch, $supplier, [
            ['stock_item_id' => $item->id, 'quantity_milli' => 10000, 'unit_cost_minor' => 1000],
            ['description' => 'Gas bottle', 'unit_code' => 'ea', 'quantity_milli' => 5000, 'unit_cost_minor' => 20000],
        ]);
        $this->receive($owner, $order, [0 => 4000])->assertOk();

        $snapshot = fn () => [
            StockMovement::withoutGlobalScopes()->count(),
            StockLevel::withoutGlobalScopes()->get(['branch_id', 'stock_item_id', 'quantity_milli', 'average_cost_minor'])->toArray(),
            DB::table('purchase_order_lines')->orderBy('id')->pluck('received_milli')->all(),
        ];
        $before = $snapshot();

        $closed = $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$order['id']}/close", [
            'reason' => 'refused_on_delivery', 'note' => 'Six crates arrived broken',
        ])->assertOk()->json('data');

        $this->assertSame('received', $closed['status']);
        $this->assertTrue($closed['closed_short']);
        $this->assertSame('refused_on_delivery', $closed['close_reason']);
        $this->assertSame('Six crates arrived broken', $closed['close_note']);
        $this->assertFalse($closed['is_open']);
        $this->assertSame([6000, 5000], array_column($closed['lines'], 'not_coming_milli'));
        $this->assertSame($before, $snapshot(), 'closing short writes no movement and changes no level or receipt');

        $event = $this->event('purchase_order.closed_short', $restaurant->id);
        $this->assertNotNull($event);
        $this->assertSame('refused_on_delivery', $event['properties']['reason']);
        $this->assertSame([6000, 5000], array_column($event['properties']['not_coming'], 'quantity_milli'));

        // Finished: no more receipts, no cancel.
        $this->receive($owner, $closed, [0 => 1000])->assertStatus(409)->assertJsonPath('code', 'PO_NOT_OPEN');
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$order['id']}/cancel")->assertStatus(409)->assertJsonPath('code', 'PO_CANNOT_CANCEL');
        $this->assertSame($before, $snapshot());

        // An order that all arrived is not "closed short".
        $whole = $this->sentOrder($owner, $branch, $supplier, [['stock_item_id' => $item->id, 'quantity_milli' => 1000, 'unit_cost_minor' => 1000]]);
        $this->receive($owner, $whole, [0 => 1000])->assertJsonPath('data.closed_short', false)->assertJsonPath('data.lines.0.not_coming_milli', 0);
    }

    public function test_a_stale_close_after_the_rest_arrived_is_refused(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $item = $this->stockItem($restaurant);
        $order = $this->sentOrder($owner, $branch, $supplier, [['stock_item_id' => $item->id, 'quantity_milli' => 10000, 'unit_cost_minor' => 1000]]);
        $this->receive($owner, $order, [0 => 4000])->assertOk();

        $stale = PurchaseOrder::withoutGlobalScopes()->findOrFail($order['id']);
        $this->assertSame(PurchaseStatus::PARTIALLY_RECEIVED, $stale->status);
        $this->receive($owner, $order, [0 => 6000])->assertJsonPath('data.status', 'received');

        try {
            app(PurchaseOrderService::class)->closeShort($stale, PurchaseCloseReason::NO_LONGER_NEEDED, null, $owner);
            $this->fail('Closing short an order that has since arrived in full must be refused.');
        } catch (PurchasingRefusal $e) {
            $this->assertSame('PO_CANNOT_CLOSE_SHORT', $e->refusal);
        }
        $this->assertNull($stale->fresh()->closed_short_at);
    }

    // -------------------------------------------------------------- branches

    public function test_a_branch_with_invoices_or_payments_cannot_be_deleted(): void
    {
        [$restaurant, $owner, , $supplier] = $this->scene();
        $billed = $this->branch($restaurant, 'Billed');
        $paid = $this->branch($restaurant, 'Paid');
        $empty = $this->branch($restaurant, 'Empty');
        $this->invoice($owner, $billed, $supplier);
        $this->pay($owner, $paid, $supplier, 1000)->assertCreated();

        $this->actingAs($owner)->deleteJson("/api/dashboard/branches/{$billed->id}")->assertStatus(409);
        $this->actingAs($owner)->deleteJson("/api/dashboard/branches/{$paid->id}")->assertStatus(409);
        $this->actingAs($owner)->deleteJson("/api/dashboard/branches/{$empty->id}")->assertOk();
        $this->assertNotNull(Branch::withoutGlobalScopes()->find($billed->id));
        $this->assertNotNull(Branch::withoutGlobalScopes()->find($paid->id));
    }

    public function test_invoice_writes_are_audited(): void
    {
        [$restaurant, $owner, $branch, $supplier] = $this->scene();
        $bill = $this->invoice($owner, $branch, $supplier, ['number' => 'AUD-1']);
        $this->actingAs($owner)->putJson("/api/dashboard/supplier-invoices/{$bill['id']}", $this->invoiceBody($branch, $supplier, ['number' => 'AUD-1']))->assertOk();

        $created = $this->event('supplier_invoice.created', $restaurant->id);
        $this->assertNotNull($created);
        $this->assertSame(100000, $created['properties']['total_minor']);
        $this->assertNotNull($this->event('supplier_invoice.updated', $restaurant->id));
    }
}
