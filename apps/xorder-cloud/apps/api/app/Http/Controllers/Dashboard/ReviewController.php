<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\ReviewStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\ReviewResource;
use App\Models\InternalReview;
use App\Models\ReviewInternalNote;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class ReviewController extends Controller
{
    /** Filtered review list, latest first. */
    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'rating' => ['sometimes', 'integer', 'between:1,5'],
            'branch_id' => ['sometimes', 'integer'],
            'dining_area_id' => ['sometimes', 'integer'],
            'table_id' => ['sometimes', 'integer'],
            'status' => ['sometimes', Rule::in(ReviewStatus::values())],
            'contact_permission' => ['sometimes', 'boolean'],
            'date_from' => ['sometimes', 'date'],
            'date_to' => ['sometimes', 'date'],
        ]);

        $reviews = InternalReview::with(['table', 'diningArea'])
            ->when($request->filled('rating'), fn ($q) => $q->where('rating', $request->integer('rating')))
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            ->when($request->filled('dining_area_id'), fn ($q) => $q->where('dining_area_id', $request->integer('dining_area_id')))
            ->when($request->filled('table_id'), fn ($q) => $q->where('table_id', $request->integer('table_id')))
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->input('status')))
            ->when($request->filled('contact_permission'), fn ($q) => $q->where('contact_permission', $request->boolean('contact_permission')))
            ->when($request->filled('date_from'), fn ($q) => $q->whereDate('created_at', '>=', $request->date('date_from')))
            ->when($request->filled('date_to'), fn ($q) => $q->whereDate('created_at', '<=', $request->date('date_to')))
            ->latest('id')
            ->paginate(20);

        return ReviewResource::collection($reviews)->response();
    }

    /** Aggregate stats for the summary tiles. */
    public function summary(): JsonResponse
    {
        $threshold = (int) config('platform.review_low_rating_threshold', 3);

        $count = InternalReview::count();
        $average = $count > 0 ? round((float) InternalReview::avg('rating'), 1) : 0.0;
        $lowCount = InternalReview::where('rating', '<=', $threshold)->count();

        $byRating = [];
        foreach (range(1, 5) as $star) {
            $byRating[$star] = InternalReview::where('rating', $star)->count();
        }

        return response()->json([
            'average' => $average,
            'count' => $count,
            'low_count' => $lowCount,
            'by_rating' => $byRating,
        ]);
    }

    public function show(InternalReview $review): JsonResponse
    {
        $review->load(['table', 'diningArea', 'notes.user']);

        return response()->json(['data' => ReviewResource::make($review)]);
    }

    public function updateStatus(Request $request, InternalReview $review): JsonResponse
    {
        $request->validate([
            'status' => ['required', Rule::in(ReviewStatus::values())],
        ]);

        $review->status = $request->input('status');
        $review->save();

        return response()->json([
            'data' => ReviewResource::make($review->fresh()->load(['table', 'diningArea'])),
            'message' => __('xorder.messages.review_status_updated'),
        ]);
    }

    public function addNote(Request $request, InternalReview $review): JsonResponse
    {
        $request->validate([
            'note' => ['required', 'string', 'max:2000'],
        ]);

        $note = new ReviewInternalNote([
            'note' => $request->input('note'),
            'user_id' => $request->user()?->id,
        ]);
        $note->internal_review_id = $review->id;
        $note->save();

        return response()->json([
            'data' => ReviewResource::make($review->fresh()->load(['table', 'diningArea', 'notes.user'])),
            'message' => __('xorder.messages.review_note_added'),
        ]);
    }
}
