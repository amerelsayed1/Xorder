<?php

namespace Tests\Feature\Pos;

use App\Enums\TenantCapability;
use App\Models\Branch;
use App\Models\FinancialAccount;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\TenderAccountDefault;
use App\Models\TenderType;
use App\Models\User;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;

/**
 * XORD-015 stage 1: financial accounts (cash, bank, wallet), optionally tied to
 * a branch, and the account each payment method pays into per branch.
 *
 * Nothing is posted to an account in this stage; these tests cover who may
 * manage them, tenant isolation, the default rules and the bundle the till
 * downloads.
 */
class FinancialAccountsTest extends PosTestCase
{
    private function account(array $overrides = [], ?Restaurant $restaurant = null): FinancialAccount
    {
        $restaurant ??= $this->restaurant;
        $account = new FinancialAccount(array_merge(['name' => 'Cash drawer', 'kind' => 'cash'], $overrides));
        $account->restaurant_id = $restaurant->id;
        $account->currency = 'EGP';
        $account->save();

        return $account;
    }

    private function tender(?Restaurant $restaurant = null, string $kind = 'card'): TenderType
    {
        $tender = new TenderType(['name' => ucfirst($kind), 'kind' => $kind]);
        $tender->restaurant_id = ($restaurant ?? $this->restaurant)->id;
        $tender->save();

        return $tender;
    }

    private function otherTenant(): Restaurant
    {
        $other = Restaurant::factory()->create(['currency' => 'EGP']);
        $other->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);

        return $other;
    }

    private function staffWith(array $capabilities): User
    {
        $role = new Role(['name' => 'Role '.uniqid()]);
        $role->forceFill([
            'restaurant_id' => $this->restaurant->id,
            'capabilities' => TenantCapability::expand($capabilities),
            'is_system' => false,
        ])->save();

        return User::factory()->staff($this->restaurant->id, $role->id)->create();
    }

    private function second_branch(Restaurant $restaurant): Branch
    {
        $branch = new Branch(['name_en' => 'Zamalek', 'code' => 'ZAM', 'supported_order_types' => ['dine_in']]);
        $branch->restaurant_id = $restaurant->id;
        $branch->save();

        return $branch;
    }

    private function bundle(): array
    {
        ['token' => $token] = $this->claimTerminal();

        return $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token))->assertOk()->json();
    }

    // ----------------------------------------------------------- accounts

    public function test_the_owner_adds_an_account_and_the_server_sets_the_currency(): void
    {
        $response = $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', [
            'name' => '  CIB main  ', 'kind' => 'bank', 'reference_label' => 'CIB 4521',
            // A client cannot choose the currency: it is the restaurant's.
            'currency' => 'USD',
        ])->assertCreated();

        $response->assertJsonPath('data.name', 'CIB main')
            ->assertJsonPath('data.kind', 'bank')
            ->assertJsonPath('data.currency', 'EGP')
            ->assertJsonPath('data.branch_id', null)
            ->assertJsonPath('data.is_active', true);

        $this->actingAs($this->owner)->getJson('/api/dashboard/financial-accounts')
            ->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_an_account_can_be_tied_to_one_of_the_restaurants_branches(): void
    {
        $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', [
            'name' => 'Maadi drawer', 'kind' => 'cash', 'branch_id' => $this->branch->id,
        ])->assertCreated()->assertJsonPath('data.branch_id', $this->branch->id);
    }

    public function test_validation_refuses_a_bad_kind_a_duplicate_name_and_an_account_number(): void
    {
        $this->account(['name' => 'Cash drawer']);

        $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', ['name' => 'X', 'kind' => 'crypto'])
            ->assertStatus(422)->assertJsonValidationErrors('kind');

        $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', ['name' => ' Cash drawer ', 'kind' => 'cash'])
            ->assertStatus(422)->assertJsonValidationErrors('name');

        foreach (['1234567890123', '1234 5678 9012', 'EG38 0019 0005 0000 0000 2631 8000 2'] as $number) {
            $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', [
                'name' => 'Bank '.$number, 'kind' => 'bank', 'reference_label' => $number,
            ])->assertStatus(422)->assertJsonValidationErrors('reference_label');
        }

        $this->assertSame(1, FinancialAccount::count());
    }

    public function test_another_restaurants_branch_is_refused(): void
    {
        $other = $this->otherTenant();
        $foreign = $this->second_branch($other);

        $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', [
            'name' => 'Sneaky', 'kind' => 'cash', 'branch_id' => $foreign->id,
        ])->assertStatus(422)->assertJsonValidationErrors('branch_id');
    }

    public function test_another_restaurant_cannot_see_edit_or_disable_an_account(): void
    {
        $mine = $this->account(['name' => 'Mine']);
        $other = $this->otherTenant();
        $stranger = User::factory()->restaurantAdmin($other->id)->create();
        $theirs = $this->account(['name' => 'Theirs'], $other);

        $this->actingAs($stranger)->getJson('/api/dashboard/financial-accounts')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', $theirs->id);

        $this->actingAs($stranger)->putJson("/api/dashboard/financial-accounts/{$mine->id}", ['name' => 'Taken', 'kind' => 'cash'])
            ->assertNotFound();
        $this->actingAs($stranger)->deleteJson("/api/dashboard/financial-accounts/{$mine->id}")->assertNotFound();

        $this->assertSame('Mine', $mine->fresh()->name);
        $this->assertTrue($mine->fresh()->is_active);
    }

    public function test_settings_editors_can_read_accounts_but_only_finance_managers_can_write(): void
    {
        $this->account();
        $settings = $this->staffWith(['settings.update']);
        $manager = $this->staffWith(['finance.accounts']);

        $this->actingAs($settings)->getJson('/api/dashboard/financial-accounts')->assertOk();
        $this->actingAs($settings)->postJson('/api/dashboard/financial-accounts', ['name' => 'New', 'kind' => 'cash'])->assertForbidden();

        // finance.accounts implies settings.view, so the role can also read.
        $this->actingAs($manager)->getJson('/api/dashboard/financial-accounts')->assertOk();
        $this->actingAs($manager)->postJson('/api/dashboard/financial-accounts', ['name' => 'New', 'kind' => 'cash'])->assertCreated();
    }

    public function test_delete_deactivates_and_the_row_stays(): void
    {
        $account = $this->account();

        $this->actingAs($this->owner)->deleteJson("/api/dashboard/financial-accounts/{$account->id}")
            ->assertOk()->assertJsonPath('data.is_active', false);

        $this->assertNotNull(FinancialAccount::find($account->id));
    }

    public function test_an_account_is_renamed_retied_switched_off_and_back_on(): void
    {
        $zamalek = $this->second_branch($this->restaurant);
        $account = $this->account(['name' => 'Drawer', 'kind' => 'cash']);
        $url = "/api/dashboard/financial-accounts/{$account->id}";

        $this->actingAs($this->owner)->putJson($url, ['name' => 'Main drawer', 'kind' => 'cash', 'branch_id' => $this->branch->id])
            ->assertOk()->assertJsonPath('data.name', 'Main drawer')->assertJsonPath('data.branch_id', $this->branch->id);

        // Re-sending the same name is not a clash with itself: the dashboard
        // does exactly this to switch an account off and on.
        $this->actingAs($this->owner)->putJson($url, ['name' => 'Main drawer', 'kind' => 'cash', 'branch_id' => $this->branch->id, 'is_active' => false])
            ->assertOk()->assertJsonPath('data.is_active', false);
        $this->actingAs($this->owner)->putJson($url, ['name' => 'Main drawer', 'kind' => 'cash', 'branch_id' => $this->branch->id, 'is_active' => true])
            ->assertOk()->assertJsonPath('data.is_active', true);

        $this->actingAs($this->owner)->putJson($url, ['name' => 'Main drawer', 'kind' => 'bank', 'branch_id' => $zamalek->id])
            ->assertOk()->assertJsonPath('data.kind', 'bank')->assertJsonPath('data.branch_id', $zamalek->id);
    }

    public function test_an_explicit_null_is_a_validation_error_not_a_server_error(): void
    {
        foreach ([['is_active' => null], ['sort_order' => null], ['sort_order' => 1000000000000], ['sort_order' => -1]] as $bad) {
            $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', array_merge(['name' => 'X'.uniqid(), 'kind' => 'cash'], $bad))
                ->assertStatus(422)->assertJsonValidationErrors(array_key_first($bad));
        }

        $this->assertSame(0, FinancialAccount::count());
    }

    public function test_an_account_number_is_refused_in_any_script_and_in_the_name_too(): void
    {
        $numbers = [
            '٠١٢٣٤٥٦٧٨٩٠١',          // Arabic-Indic digits
            '۱۲۳۴۵۶۷۸۹۰',             // Eastern Arabic-Indic digits
            '１２３４５６７８９０',      // full-width digits
            '1234.5678.9012',         // dots between the groups
            '1234/5678/9012',
        ];
        foreach ($numbers as $number) {
            $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', ['name' => 'Ref '.uniqid(), 'kind' => 'bank', 'reference_label' => $number])
                ->assertStatus(422)->assertJsonValidationErrors('reference_label');
            $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', ['name' => $number, 'kind' => 'bank'])
                ->assertStatus(422)->assertJsonValidationErrors('name');
        }

        // A short, honest label in either language is fine.
        $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', ['name' => 'حساب البنك الأهلي', 'kind' => 'bank', 'reference_label' => 'آخر أربعة ٤٥٢١'])
            ->assertCreated();
    }

    public function test_names_are_unique_without_regard_to_case(): void
    {
        $first = $this->account(['name' => 'Cash drawer']);

        $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', ['name' => 'cash DRAWER', 'kind' => 'cash'])
            ->assertStatus(422)->assertJsonValidationErrors('name');

        // The account itself may change the case of its own name.
        $this->actingAs($this->owner)->putJson("/api/dashboard/financial-accounts/{$first->id}", ['name' => 'CASH DRAWER', 'kind' => 'cash'])
            ->assertOk();
    }

    public function test_a_branch_that_has_an_account_cannot_be_deleted_and_says_why(): void
    {
        $zamalek = $this->second_branch($this->restaurant);
        $this->account(['name' => 'Zamalek drawer', 'branch_id' => $zamalek->id]);

        $this->actingAs($this->owner)->deleteJson("/api/dashboard/branches/{$zamalek->id}")
            ->assertStatus(409)->assertJsonPath('message', __('xorder.messages.branch_has_accounts'));

        $this->assertNotNull(Branch::find($zamalek->id));
    }

    // ----------------------------------------------------------- defaults

    private function setDefault(User $user, TenderType $tender, ?int $accountId, ?int $branchId = null)
    {
        return $this->actingAs($user)->putJson('/api/dashboard/tender-account-defaults', [
            'tender_type_id' => $tender->id, 'branch_id' => $branchId, 'financial_account_id' => $accountId,
        ]);
    }

    public function test_a_business_wide_default_is_set_replaced_and_cleared_as_one_row(): void
    {
        $tender = $this->tender();
        $bank = $this->account(['name' => 'Bank', 'kind' => 'bank']);
        $wallet = $this->account(['name' => 'Wallet', 'kind' => 'wallet']);

        $this->setDefault($this->owner, $tender, $bank->id)->assertOk()
            ->assertJsonPath('data.financial_account_id', $bank->id)->assertJsonPath('data.branch_id', null);
        $this->setDefault($this->owner, $tender, $wallet->id)->assertOk();

        $this->assertSame(1, TenderAccountDefault::count());
        $this->assertSame($wallet->id, TenderAccountDefault::first()->financial_account_id);

        $this->actingAs($this->owner)->getJson('/api/dashboard/tender-account-defaults')
            ->assertOk()->assertJsonCount(1, 'data');

        $this->setDefault($this->owner, $tender, null)->assertOk();
        $this->assertSame(0, TenderAccountDefault::count());
    }

    public function test_a_branch_default_can_use_that_branchs_own_account_but_a_business_wide_one_cannot(): void
    {
        $tender = $this->tender(kind: 'cash');
        $zamalek = $this->second_branch($this->restaurant);
        $maadiDrawer = $this->account(['name' => 'Maadi drawer', 'branch_id' => $this->branch->id]);

        // Cash at Maadi -> Maadi's drawer: fine.
        $this->setDefault($this->owner, $tender, $maadiDrawer->id, $this->branch->id)->assertOk();
        // Cash at Zamalek -> Maadi's drawer: another branch's account.
        $this->setDefault($this->owner, $tender, $maadiDrawer->id, $zamalek->id)
            ->assertStatus(422)->assertJsonValidationErrors('financial_account_id');
        // Cash everywhere -> Maadi's drawer: a branch account cannot be the fallback.
        $this->setDefault($this->owner, $tender, $maadiDrawer->id, null)
            ->assertStatus(422)->assertJsonValidationErrors('financial_account_id');

        $this->assertSame(1, TenderAccountDefault::count());
    }

    public function test_a_shared_account_can_be_a_default_for_any_branch(): void
    {
        $tender = $this->tender();
        $bank = $this->account(['name' => 'Bank', 'kind' => 'bank']);

        $this->setDefault($this->owner, $tender, $bank->id, $this->branch->id)->assertOk();
        $this->setDefault($this->owner, $tender, $bank->id, null)->assertOk();

        $this->assertSame(2, TenderAccountDefault::count());
    }

    public function test_a_disabled_account_cannot_be_a_default_and_a_default_cannot_be_disabled(): void
    {
        $tender = $this->tender();
        $bank = $this->account(['name' => 'Bank', 'kind' => 'bank']);
        $old = $this->account(['name' => 'Old', 'is_active' => false]);

        $this->setDefault($this->owner, $tender, $old->id)->assertStatus(422)->assertJsonValidationErrors('financial_account_id');

        $this->setDefault($this->owner, $tender, $bank->id)->assertOk();
        $this->actingAs($this->owner)->deleteJson("/api/dashboard/financial-accounts/{$bank->id}")
            ->assertStatus(422)->assertJsonValidationErrors('is_active');
        $this->actingAs($this->owner)->putJson("/api/dashboard/financial-accounts/{$bank->id}", ['name' => 'Bank', 'kind' => 'bank', 'is_active' => false])
            ->assertStatus(422)->assertJsonValidationErrors('is_active');

        $this->assertTrue($bank->fresh()->is_active);
    }

    public function test_tying_a_default_account_to_another_branch_is_refused(): void
    {
        $tender = $this->tender();
        $bank = $this->account(['name' => 'Bank', 'kind' => 'bank']);
        $zamalek = $this->second_branch($this->restaurant);

        $this->setDefault($this->owner, $tender, $bank->id, null)->assertOk();

        $this->actingAs($this->owner)->putJson("/api/dashboard/financial-accounts/{$bank->id}", [
            'name' => 'Bank', 'kind' => 'bank', 'branch_id' => $zamalek->id,
        ])->assertStatus(422)->assertJsonValidationErrors('branch_id');
    }

    public function test_only_finance_managers_set_defaults_a_settings_editor_cannot_redirect_the_money(): void
    {
        $tender = $this->tender();
        $bank = $this->account(['name' => 'Bank', 'kind' => 'bank']);

        $this->setDefault($this->staffWith(['settings.update']), $tender, $bank->id)->assertForbidden();
        $this->setDefault($this->staffWith(['finance.accounts']), $tender, $bank->id)->assertOk();
    }

    public function test_defaults_never_cross_the_tenant_boundary(): void
    {
        $other = $this->otherTenant();
        $theirTender = $this->tender($other);
        $theirAccount = $this->account(['name' => 'Theirs'], $other);
        $myTender = $this->tender();
        $myAccount = $this->account(['name' => 'Mine']);

        $this->setDefault($this->owner, $theirTender, $myAccount->id)->assertStatus(422)->assertJsonValidationErrors('tender_type_id');
        $this->setDefault($this->owner, $myTender, $theirAccount->id)->assertStatus(422)->assertJsonValidationErrors('financial_account_id');
        $this->assertSame(0, TenderAccountDefault::withoutGlobalScopes()->count());
    }

    // ------------------------------------------------------------- bundle

    public function test_the_bundle_carries_accounts_and_defaults_and_leaves_tender_types_as_they_were(): void
    {
        $bank = $this->account(['name' => 'Bank', 'kind' => 'bank', 'reference_label' => 'CIB 4521']);
        $other = $this->otherTenant();
        $this->account(['name' => 'Not mine'], $other);

        $first = $this->bundle();
        $card = collect($first['money']['tender_types'])->firstWhere('kind', 'card');
        $this->setDefault($this->owner, TenderType::find($card['id']), $bank->id)->assertOk();

        $second = $this->bundle();
        $money = $second['money'];

        $this->assertSame(['Bank'], collect($money['financial_accounts'])->pluck('name')->all());
        $this->assertSame(
            ['id', 'name', 'kind', 'currency', 'branch_id', 'reference_label', 'is_active', 'sort_order'],
            array_keys($money['financial_accounts'][0]),
        );
        $this->assertSame(
            [['tender_type_id' => $card['id'], 'branch_id' => null, 'financial_account_id' => $bank->id]],
            $money['tender_account_defaults'],
        );
        // The existing payment-method shape is untouched.
        $this->assertSame(['id', 'name', 'kind', 'is_active', 'sort_order'], array_keys($money['tender_types'][0]));
    }

    public function test_changing_an_account_or_a_default_moves_the_config_version(): void
    {
        $tender = $this->tender();
        $before = (int) $this->restaurant->fresh()->pos_config_version;

        $account = $this->actingAs($this->owner)->postJson('/api/dashboard/financial-accounts', ['name' => 'Bank', 'kind' => 'bank'])
            ->assertCreated()->json('data');
        $afterAccount = (int) $this->restaurant->fresh()->pos_config_version;
        $this->assertGreaterThan($before, $afterAccount);

        $this->setDefault($this->owner, $tender, $account['id'])->assertOk();
        $this->assertGreaterThan($afterAccount, (int) $this->restaurant->fresh()->pos_config_version);
    }

    public function test_the_activity_line_for_a_default_says_which_method_pays_into_which_account(): void
    {
        $dir = storage_path('framework/testing/audit-'.uniqid());
        config(['platform.activity_log_file' => true, 'logging.channels.activity.path' => $dir.'/activity.log']);
        Log::forgetChannel('activity');

        try {
            $card = $this->tender();
            $bank = $this->account(['name' => 'CIB main', 'kind' => 'bank']);
            $this->setDefault($this->owner, $card, $bank->id)->assertOk();
            $this->setDefault($this->owner, $card, null)->assertOk();

            $file = $dir.'/activity-'.now()->format('Y-m-d').'.log';
            $events = collect(array_map(fn ($l) => json_decode($l, true), array_values(array_filter(explode("\n", (string) file_get_contents($file))))));

            $created = $events->firstWhere('action', 'tender_account_default.created');
            $deleted = $events->firstWhere('action', 'tender_account_default.deleted');

            $this->assertNotNull($created, 'creating a default is recorded');
            $this->assertStringContainsString('Card pays into CIB main (all branches)', $created['description'] ?? '');
            $this->assertNotNull($deleted, 'clearing a default is recorded');
            $this->assertStringContainsString('Card pays into CIB main', $deleted['description'] ?? '');
            $this->assertNotNull($events->firstWhere('action', 'financial_account.created'));
        } finally {
            Log::forgetChannel('activity');
            File::deleteDirectory($dir);
        }
    }

    public function test_the_bundle_never_carries_another_restaurants_defaults(): void
    {
        $other = $this->otherTenant();
        $theirTender = $this->tender($other);
        $theirAccount = $this->account(['name' => 'Theirs'], $other);
        $row = new TenderAccountDefault(['tender_type_id' => $theirTender->id, 'financial_account_id' => $theirAccount->id]);
        $row->restaurant_id = $other->id;
        $row->save();

        $money = $this->bundle()['money'];

        $this->assertSame([], $money['financial_accounts']);
        $this->assertSame([], $money['tender_account_defaults']);
    }

    public function test_the_new_capability_is_a_standalone_verb_that_implies_only_opening_settings(): void
    {
        $this->assertSame('finance.accounts', TenantCapability::FINANCE_ACCOUNTS->value);
        $this->assertSame('finance', TenantCapability::FINANCE_ACCOUNTS->resource());
        $this->assertSame(TenantCapability::SETTINGS_VIEW, TenantCapability::FINANCE_ACCOUNTS->implies());
        $this->assertEqualsCanonicalizing(['finance.accounts', 'settings.view'], TenantCapability::expand(['finance.accounts']));
        $this->assertArrayNotHasKey('finance.accounts', TenantCapability::legacyManageMap());
    }
}
