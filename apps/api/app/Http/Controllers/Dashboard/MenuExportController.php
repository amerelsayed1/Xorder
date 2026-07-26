<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\MenuItem;
use App\Support\CsvSafe;
use Illuminate\Http\Request;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx as XlsxWriter;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Exports the restaurant's menu (categories + items) to CSV or Excel.
 *
 * The column layout mirrors what MenuImportController accepts, so an exported
 * file can be edited and re-imported without loss (a clean round-trip). Both
 * languages are emitted explicitly (name_en/name_ar, category_en/category_ar)
 * regardless of the restaurant's default language. A read, not a write — stays
 * available even when the subscription is read-only.
 */
class MenuExportController extends Controller
{
    /** @var array<int,string> */
    private const HEADERS = [
        'category_en', 'category_ar', 'name_en', 'name_ar',
        'description_en', 'description_ar', 'price', 'discounted_price',
        'available', 'featured', 'image_url',
    ];

    /** GET dashboard/items/export?format=csv|xlsx */
    public function export(Request $request): StreamedResponse
    {
        $format = $request->string('format')->toString() === 'xlsx' ? 'xlsx' : 'csv';

        // Tenant-scoped by the MenuItem global scope, same as the index.
        $items = MenuItem::query()
            ->with('category')
            ->orderBy('category_id')
            ->orderBy('display_order')
            ->orderBy('id')
            ->get();

        $rows = $items->map(fn (MenuItem $it) => [
            $it->category?->name_en,
            $it->category?->name_ar,
            $it->name_en,
            $it->name_ar,
            $it->description_en,
            $it->description_ar,
            $it->price,
            $it->discounted_price,
            $it->is_available ? 'yes' : 'no',
            $it->is_featured ? 'yes' : 'no',
            $it->image_url,
        ])->all();

        return $format === 'xlsx'
            ? $this->exportXlsx(self::HEADERS, $rows)
            : $this->exportCsv(self::HEADERS, $rows);
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
                fputcsv($out, CsvSafe::row($row));
            }
            fclose($out);
        }, 'menu.csv', ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    /**
     * @param  array<int,string>  $headers
     * @param  array<int,array<int,mixed>>  $rows
     */
    private function exportXlsx(array $headers, array $rows): StreamedResponse
    {
        $spreadsheet = new Spreadsheet;
        $sheet = $spreadsheet->getActiveSheet();
        $sheet->setTitle('Menu');
        $sheet->fromArray($headers, null, 'A1');
        if ($rows !== []) {
            $sheet->fromArray(array_map([CsvSafe::class, 'row'], $rows), null, 'A2');
        }

        return response()->streamDownload(function () use ($spreadsheet) {
            (new XlsxWriter($spreadsheet))->save('php://output');
        }, 'menu.xlsx', [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ]);
    }
}
