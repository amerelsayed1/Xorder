<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Services\ReportService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx as XlsxWriter;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Phase 4 — Product Analytics / Reports (admin-only, feature: product_analytics).
 *
 * All reads. Aggregation lives in ReportService; the controller only validates
 * filters and shapes the response / export.
 */
class ReportController extends Controller
{
    public function __construct(private readonly ReportService $reports) {}

    /** GET dashboard/reports/products-by-time */
    public function productsByTime(Request $request): JsonResponse
    {
        $filters = $this->validateFilters($request);
        $restaurant = $request->user()->restaurant;

        return response()->json([
            'data' => $this->reports->productsByTime($restaurant, $filters),
            'meta' => [
                'timezone' => $restaurant->timezone ?: config('app.timezone', 'UTC'),
                'periods' => array_column((array) config('platform.report_periods', []), 'key'),
            ],
        ]);
    }

    /** GET dashboard/reports/dining-areas */
    public function diningAreas(Request $request): JsonResponse
    {
        $filters = $this->validateFilters($request);
        $restaurant = $request->user()->restaurant;

        return response()->json([
            'data' => $this->reports->diningAreas($restaurant, $filters),
        ]);
    }

    /** GET dashboard/reports/products-by-time/export?format=csv|xlsx */
    public function export(Request $request): StreamedResponse
    {
        $filters = $this->validateFilters($request);
        $format = $request->string('format')->toString() === 'xlsx' ? 'xlsx' : 'csv';
        $restaurant = $request->user()->restaurant;

        $rows = $this->reports->productsTable($restaurant, $filters);

        $headers = [
            'Product', 'Quantity', 'Orders', 'Total sales',
            'Avg qty / order', '% of orders', 'Most active period',
        ];

        $data = array_map(fn (array $r) => [
            $r['name'],
            $r['quantity'],
            $r['orders_containing'],
            $r['total_sales'],
            $r['avg_qty_per_order'],
            $r['pct_of_orders'],
            $r['most_active_period'] ?? '',
        ], $rows);

        return $format === 'xlsx'
            ? $this->exportXlsx($headers, $data)
            : $this->exportCsv($headers, $data);
    }

    /**
     * @return array<string,mixed>
     */
    private function validateFilters(Request $request): array
    {
        $validated = $request->validate([
            'date_from' => ['sometimes', 'nullable', 'date'],
            'date_to' => ['sometimes', 'nullable', 'date'],
            'branch_id' => ['sometimes', 'nullable', 'integer'],
            'dining_area_id' => ['sometimes', 'nullable', 'integer'],
            'area_type' => ['sometimes', 'nullable', 'string', 'max:40'],
            'order_type' => ['sometimes', 'nullable', Rule::in(['pickup', 'delivery', 'dine_in'])],
            'include_cancelled' => ['sometimes', 'boolean'],
            'group' => ['sometimes', Rule::in(['period', 'hour'])],
        ]);

        $validated['include_cancelled'] = $request->boolean('include_cancelled');

        return $validated;
    }

    /**
     * @param  array<int,string>  $headers
     * @param  array<int,array<int,mixed>>  $rows
     */
    private function exportCsv(array $headers, array $rows): StreamedResponse
    {
        return response()->streamDownload(function () use ($headers, $rows) {
            $out = fopen('php://output', 'w');
            fwrite($out, "\xEF\xBB\xBF"); // UTF-8 BOM for Excel/Arabic
            fputcsv($out, $headers);
            foreach ($rows as $row) {
                fputcsv($out, $row);
            }
            fclose($out);
        }, 'products-by-time.csv', ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    /**
     * @param  array<int,string>  $headers
     * @param  array<int,array<int,mixed>>  $rows
     */
    private function exportXlsx(array $headers, array $rows): StreamedResponse
    {
        $spreadsheet = new Spreadsheet;
        $sheet = $spreadsheet->getActiveSheet();
        $sheet->setTitle('Products by time');
        $sheet->fromArray($headers, null, 'A1');
        if ($rows !== []) {
            $sheet->fromArray($rows, null, 'A2');
        }

        $filename = 'products-by-time.xlsx';

        return response()->streamDownload(function () use ($spreadsheet) {
            (new XlsxWriter($spreadsheet))->save('php://output');
        }, $filename, [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ]);
    }
}
