<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreFinancialAccountRequest;
use App\Http\Requests\Dashboard\UpdateFinancialAccountRequest;
use App\Models\FinancialAccount;
use App\Models\Restaurant;
use App\Models\TenderAccountDefault;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\JsonResponse;
use Illuminate\Validation\ValidationException;

/**
 * XORD-015, stage 1: the business's cash, bank and wallet accounts.
 *
 * Reads sit behind `settings.view` (the payment-method editor needs the list);
 * writes behind `finance.accounts`. DELETE deactivates — an account is never
 * removed, so anything that later names one keeps a row to point at. Nothing is
 * posted to an account in this stage; there are no balances.
 */
class FinancialAccountController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json([
            'data' => FinancialAccount::orderBy('sort_order')->orderBy('id')->get(),
        ]);
    }

    public function store(StoreFinancialAccountRequest $request): JsonResponse
    {
        $account = new FinancialAccount($request->validated());
        // The server's word, never the client's: an account is in the
        // restaurant's own currency.
        $account->currency = Restaurant::query()->whereKey($request->user()->restaurant_id)->firstOrFail()->currency->value;
        $this->persist(fn () => $account->save());

        return response()->json(['data' => $account->fresh(), 'message' => __('xorder.messages.saved')], 201);
    }

    public function update(UpdateFinancialAccountRequest $request, FinancialAccount $financialAccount): JsonResponse
    {
        $data = $request->validated();

        $this->guardBranchChange($financialAccount, $data);
        $this->guardDeactivation($financialAccount, $data['is_active'] ?? $financialAccount->is_active);

        $this->persist(fn () => $financialAccount->update($data));

        return response()->json(['data' => $financialAccount->fresh(), 'message' => __('xorder.messages.saved')]);
    }

    /**
     * Two people saving the same name at once both pass the request's check and
     * one meets the database's unique key: answer it as the validation error it
     * is, not as a 500.
     */
    private function persist(callable $write): void
    {
        try {
            $write();
        } catch (UniqueConstraintViolationException) {
            throw ValidationException::withMessages([
                'name' => [__('xorder.validation.account_name_taken')],
            ]);
        }
    }

    public function destroy(FinancialAccount $financialAccount): JsonResponse
    {
        $this->guardDeactivation($financialAccount, false);

        $financialAccount->update(['is_active' => false]);

        return response()->json(['data' => $financialAccount->fresh(), 'message' => __('xorder.messages.saved')]);
    }

    /** An account that is somebody's default cannot be switched off until it is replaced. */
    private function guardDeactivation(FinancialAccount $account, bool $willBeActive): void
    {
        if ($willBeActive || ! $account->is_active) {
            return;
        }

        if (TenderAccountDefault::where('financial_account_id', $account->id)->exists()) {
            throw ValidationException::withMessages([
                'is_active' => [__('xorder.validation.account_is_default')],
            ]);
        }
    }

    /**
     * Tying an account to a branch must not strand a default that points at it
     * from another branch (or from the business-wide fallback).
     *
     * @param  array<string,mixed>  $data
     */
    private function guardBranchChange(FinancialAccount $account, array $data): void
    {
        if (! array_key_exists('branch_id', $data) || $data['branch_id'] === null) {
            return;
        }

        $strands = TenderAccountDefault::where('financial_account_id', $account->id)
            ->where('branch_key', '!=', (int) $data['branch_id'])
            ->exists();

        if ($strands) {
            throw ValidationException::withMessages([
                'branch_id' => [__('xorder.validation.account_is_default')],
            ]);
        }
    }
}
