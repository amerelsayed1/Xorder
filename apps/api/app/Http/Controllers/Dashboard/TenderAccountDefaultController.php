<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\SetTenderAccountDefaultRequest;
use App\Models\TenderAccountDefault;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\JsonResponse;

/**
 * XORD-015, stage 1: which account each payment method pays into, per branch.
 *
 * One endpoint sets or clears a single (method, branch) pair; a null branch is
 * the business-wide fallback. Reads sit behind `settings.view`, writes behind
 * `finance.accounts` (see the request). Changing a default rewrites nothing that
 * already happened: in this stage nothing is recorded against an account.
 */
class TenderAccountDefaultController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json([
            'data' => TenderAccountDefault::orderBy('tender_type_id')->orderBy('branch_key')
                ->get(['id', 'tender_type_id', 'branch_id', 'financial_account_id']),
        ]);
    }

    public function update(SetTenderAccountDefaultRequest $request): JsonResponse
    {
        $data = $request->validated();
        $branchKey = (int) ($data['branch_id'] ?? 0);

        $row = TenderAccountDefault::where('tender_type_id', $data['tender_type_id'])
            ->where('branch_key', $branchKey)
            ->first();

        if (($data['financial_account_id'] ?? null) === null) {
            $row?->delete();

            return response()->json(['data' => null, 'message' => __('xorder.messages.saved')]);
        }

        try {
            $row = $this->save($row, $data);
        } catch (UniqueConstraintViolationException) {
            // Two admins set the same pair at once: the loser updates the winner's row.
            $row = $this->save(
                TenderAccountDefault::where('tender_type_id', $data['tender_type_id'])->where('branch_key', $branchKey)->firstOrFail(),
                $data,
            );
        }

        return response()->json([
            'data' => $row->only(['id', 'tender_type_id', 'branch_id', 'financial_account_id']),
            'message' => __('xorder.messages.saved'),
        ]);
    }

    /** @param array<string,mixed> $data */
    private function save(?TenderAccountDefault $row, array $data): TenderAccountDefault
    {
        $row ??= new TenderAccountDefault([
            'tender_type_id' => $data['tender_type_id'],
            'branch_id' => $data['branch_id'] ?? null,
        ]);
        $row->financial_account_id = $data['financial_account_id'];
        $row->save();

        return $row;
    }
}
