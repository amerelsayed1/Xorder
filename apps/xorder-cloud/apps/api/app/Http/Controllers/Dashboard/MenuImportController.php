<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\MenuItem;
use App\Services\PlanLimitService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Validation\ValidationException;
use PhpOffice\PhpSpreadsheet\Reader\Csv as CsvReader;
use PhpOffice\PhpSpreadsheet\Reader\Xls as XlsReader;
use PhpOffice\PhpSpreadsheet\Reader\Xlsx as XlsxReader;

/**
 * Bulk-imports categories and menu items from an uploaded CSV or Excel file.
 *
 * The file is a flat sheet: one row per item, with a header row naming the
 * columns. Categories are created on demand and reused by name. Existing items
 * (matched by name within their category) are updated in place — re-running the
 * same file is safe (upsert), not duplicating.
 *
 * Recognised headers (case-insensitive, spaces or underscores):
 *   id | item_id                            (stable ids from an export; matched
 *   category_id                              first so renamed rows update in
 *                                            place instead of duplicating)
 *   category | category_en | category_ar   (a plain "category" maps to the
 *   name | name_en | name_ar                 restaurant's default language)
 *   description | description_en | description_ar
 *   price          (required, numeric)
 *   discounted_price | sale_price
 *   available | is_available   (yes/no/true/false/1/0/نعم/لا)
 *   featured  | is_featured
 *   image_url | image | photo | photo_url   (a plain http(s) link)
 */
class MenuImportController extends Controller
{
    private const MAX_NAME = 150;

    private const MAX_DESC = 2000;

    private const MAX_URL = 2048;

    public function import(Request $request, PlanLimitService $limits): JsonResponse
    {
        $request->validate([
            'file' => ['required', 'file', 'mimes:csv,txt,xlsx,xls', 'max:5120'],
        ]);

        $rows = $this->readRows($request->file('file'));
        if (count($rows) < 2) {
            return response()->json(['message' => __('xorder.messages.import_empty')], 422);
        }

        $header = $this->headerMap(array_shift($rows));
        if (! isset($header['price']) || ! $this->hasAny($header, ['name', 'name_en', 'name_ar'])) {
            return response()->json(['message' => __('xorder.messages.import_bad_headers')], 422);
        }

        $restaurant = $request->user()->restaurant;
        $defaultLang = $restaurant->default_language->value; // 'ar' | 'en'

        // Tenant-scoped category cache, keyed by lowercased name (either language).
        $categories = Category::all();
        $catByName = [];
        foreach ($categories as $c) {
            $this->indexCategory($catByName, $c);
        }
        $nextCatOrder = (int) (Category::max('display_order') ?? -1) + 1;

        $summary = ['categories_created' => 0, 'items_created' => 0, 'items_updated' => 0, 'skipped' => 0, 'errors' => []];

        foreach ($rows as $i => $raw) {
            $line = $i + 2; // 1-based, +1 for the header we shifted off
            try {
                $row = $this->mapRow($header, $raw, $defaultLang);
                if ($row === null) {
                    continue; // blank row
                }
                if ($row['name_en'] === null && $row['name_ar'] === null) {
                    $summary['errors'][] = ['row' => $line, 'message' => __('xorder.messages.import_row_no_name')];

                    continue;
                }
                if ($row['category_id'] === null && $row['cat_en'] === null && $row['cat_ar'] === null) {
                    $summary['errors'][] = ['row' => $line, 'message' => __('xorder.messages.import_row_no_category')];

                    continue;
                }
                if ($row['price'] === null) {
                    $summary['errors'][] = ['row' => $line, 'message' => __('xorder.messages.import_row_bad_price')];

                    continue;
                }

                // Resolve the category by stable id first (an exported file carries
                // it) so a renamed category updates in place instead of spawning a
                // duplicate; otherwise match/create by name.
                $category = $row['category_id'] !== null ? Category::find($row['category_id']) : null;
                if ($category !== null) {
                    $this->syncCategoryNames($category, $row);
                    $this->indexCategory($catByName, $category);
                } else {
                    $category = $this->resolveCategory($catByName, $row, $nextCatOrder, $summary);
                }

                // Match the item by stable id first (same reason), else by name
                // within the category.
                $existing = $row['id'] !== null ? MenuItem::find($row['id']) : null;
                if ($existing === null) {
                    $existing = $this->findItem($category, $row);
                }
                if ($existing) {
                    $attrs = $this->itemAttributes($row);
                    // A blank image cell must never wipe an item's existing photo —
                    // images aren't retypable data, and most imports won't carry the
                    // column at all. Only overwrite when a URL is actually supplied.
                    if ($attrs['image_url'] === null) {
                        unset($attrs['image_url']);
                    }
                    $existing->fill($attrs);
                    // Re-home the item if its category changed since the export.
                    $existing->category_id = $category->id;
                    $existing->save();
                    $summary['items_updated']++;
                } else {
                    if ($limits->itemLimitReached($restaurant) !== null) {
                        $summary['skipped']++;
                        $summary['errors'][] = ['row' => $line, 'message' => __('xorder.messages.import_row_limit')];

                        continue;
                    }
                    $item = new MenuItem($this->itemAttributes($row));
                    $item->category_id = $category->id;
                    $item->save();
                    $summary['items_created']++;
                }
            } catch (\Throwable $e) {
                $summary['errors'][] = ['row' => $line, 'message' => $e->getMessage()];
            }
        }

        return response()->json([
            'data' => $summary,
            'message' => __('xorder.messages.import_done'),
        ]);
    }

    /** Read the sheet into a plain array of rows (first row = headers). */
    private function readRows(UploadedFile $file): array
    {
        // Pick the parser from the SNIFFED type, not the client's filename: the
        // `mimes` rule validates content, so trusting the name here would let a
        // caller aim their bytes at a different parser than the one that was
        // vetted (an OOXML zip delivered as "menu.csv", say).
        $ext = strtolower((string) $file->guessExtension()) ?: strtolower($file->getClientOriginalExtension());

        $reader = match ($ext) {
            'xlsx', 'zip' => new XlsxReader,   // OOXML sniffs as a zip container
            'xls' => new XlsReader,
            default => tap(new CsvReader, fn ($r) => $r->setInputEncoding('UTF-8')),
        };

        // Values only — never evaluate formulas, and never follow whatever
        // else a crafted workbook wants us to load.
        $reader->setReadDataOnly(true);

        try {
            $sheet = $reader->load($file->getRealPath())->getActiveSheet();
        } catch (\Throwable $e) {
            // Includes PhpSpreadsheet's XXE scanner rejecting a workbook whose
            // XML declares external entities.
            throw ValidationException::withMessages([
                'file' => __('xorder.messages.import_unreadable'),
            ]);
        }

        return $sheet->toArray(null, true, true, false); // 0-indexed columns
    }

    /** Map header labels -> column index. Lowercased, trimmed, spaces->underscores. */
    private function headerMap(array $headerRow): array
    {
        $map = [];
        foreach ($headerRow as $idx => $label) {
            $key = strtolower(trim((string) $label));
            $key = preg_replace('/\s+/', '_', $key);
            $key = $this->aliasHeader($key);
            if ($key !== '') {
                $map[$key] = $idx;
            }
        }

        return $map;
    }

    private function aliasHeader(string $key): string
    {
        return match ($key) {
            'item_id', 'menu_item_id' => 'id',
            'discount', 'discount_price', 'sale_price', 'offer_price' => 'discounted_price',
            'is_available', 'availability' => 'available',
            'is_featured', 'popular' => 'featured',
            'image', 'photo', 'photo_url', 'image_link', 'picture' => 'image_url',
            'name_english', 'title_en' => 'name_en',
            'name_arabic', 'title_ar' => 'name_ar',
            'category_english' => 'category_en',
            'category_arabic' => 'category_ar',
            default => $key,
        };
    }

    /** Extract normalized fields from one data row; null for a fully-blank row. */
    private function mapRow(array $header, array $raw, string $defaultLang): ?array
    {
        $get = function (array $keys) use ($header, $raw) {
            foreach ($keys as $k) {
                if (isset($header[$k])) {
                    $v = trim((string) ($raw[$header[$k]] ?? ''));
                    if ($v !== '') {
                        return $v;
                    }
                }
            }

            return null;
        };

        // A plain "name"/"category"/"description" maps to the default language.
        $plainName = $get(['name']);
        $plainCat = $get(['category']);
        $plainDesc = $get(['description']);

        $nameEn = $get(['name_en']) ?? ($defaultLang === 'en' ? $plainName : null);
        $nameAr = $get(['name_ar']) ?? ($defaultLang === 'ar' ? $plainName : null);
        $catEn = $get(['category_en']) ?? ($defaultLang === 'en' ? $plainCat : null);
        $catAr = $get(['category_ar']) ?? ($defaultLang === 'ar' ? $plainCat : null);
        $descEn = $get(['description_en']) ?? ($defaultLang === 'en' ? $plainDesc : null);
        $descAr = $get(['description_ar']) ?? ($defaultLang === 'ar' ? $plainDesc : null);

        $isBlank = ! $nameEn && ! $nameAr && ! $catEn && ! $catAr && $get(['price']) === null;
        if ($isBlank) {
            return null;
        }

        $price = $this->parsePrice($get(['price']));
        $discount = $this->parsePrice($get(['discounted_price']));
        if ($discount !== null && $price !== null && $discount >= $price) {
            $discount = null; // ignore a discount that isn't actually lower
        }

        return [
            'id' => $this->parseId($get(['id'])),
            'category_id' => $this->parseId($get(['category_id'])),
            'name_en' => $this->clip($nameEn, self::MAX_NAME),
            'name_ar' => $this->clip($nameAr, self::MAX_NAME),
            'cat_en' => $this->clip($catEn, self::MAX_NAME),
            'cat_ar' => $this->clip($catAr, self::MAX_NAME),
            'desc_en' => $this->clip($descEn, self::MAX_DESC),
            'desc_ar' => $this->clip($descAr, self::MAX_DESC),
            'price' => $price,
            'discounted_price' => $discount,
            'is_available' => $this->parseBool($get(['available']), true),
            'is_featured' => $this->parseBool($get(['featured']), false),
            'image_url' => $this->parseUrl($get(['image_url'])),
        ];
    }

    private function itemAttributes(array $row): array
    {
        return [
            'name_en' => $row['name_en'],
            'name_ar' => $row['name_ar'],
            'description_en' => $row['desc_en'],
            'description_ar' => $row['desc_ar'],
            'price' => $row['price'],
            'discounted_price' => $row['discounted_price'],
            'is_available' => $row['is_available'],
            'is_featured' => $row['is_featured'],
            'image_url' => $row['image_url'],
        ];
    }

    /** Find an existing category by either-language name, or create one. */
    private function resolveCategory(array &$catByName, array $row, int &$nextOrder, array &$summary): Category
    {
        foreach ([$row['cat_en'], $row['cat_ar']] as $name) {
            if ($name && isset($catByName[$this->key($name)])) {
                return $catByName[$this->key($name)];
            }
        }

        $category = Category::create([
            'name_en' => $row['cat_en'],
            'name_ar' => $row['cat_ar'],
            'display_order' => $nextOrder++,
            'is_active' => true,
        ]);
        $this->indexCategory($catByName, $category);
        $summary['categories_created']++;

        return $category;
    }

    private function findItem(Category $category, array $row): ?MenuItem
    {
        return MenuItem::where('category_id', $category->id)
            ->where(function ($q) use ($row) {
                if ($row['name_en']) {
                    $q->orWhereRaw('LOWER(name_en) = ?', [mb_strtolower($row['name_en'])]);
                }
                if ($row['name_ar']) {
                    $q->orWhere('name_ar', $row['name_ar']);
                }
            })
            ->first();
    }

    /** Keep an id-matched category's names in step with the (translated) row. */
    private function syncCategoryNames(Category $category, array $row): void
    {
        if ($row['cat_en'] !== null) {
            $category->name_en = $row['cat_en'];
        }
        if ($row['cat_ar'] !== null) {
            $category->name_ar = $row['cat_ar'];
        }
        if ($category->isDirty()) {
            $category->save();
        }
    }

    private function indexCategory(array &$catByName, Category $c): void
    {
        foreach ([$c->name_en, $c->name_ar] as $name) {
            if ($name) {
                $catByName[$this->key($name)] = $c;
            }
        }
    }

    private function key(?string $name): string
    {
        return mb_strtolower(trim((string) $name));
    }

    private function clip(?string $v, int $max): ?string
    {
        if ($v === null) {
            return null;
        }

        return mb_substr($v, 0, $max);
    }

    /** A positive integer id, or null for blank / non-numeric cells. */
    private function parseId(?string $v): ?int
    {
        if ($v === null) {
            return null;
        }
        $v = trim($v);

        return ctype_digit($v) && $v !== '0' ? (int) $v : null;
    }

    private function parsePrice(?string $v): ?float
    {
        if ($v === null) {
            return null;
        }
        // Keep digits, dot and minus; strip currency symbols, commas, spaces, Arabic digits.
        $v = strtr($v, ['٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4', '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9', '٫' => '.', '،' => '']);
        $v = preg_replace('/[^0-9.\-]/', '', $v);
        if ($v === '' || ! is_numeric($v)) {
            return null;
        }
        $n = round((float) $v, 2);

        return ($n < 0 || $n > 9999999.99) ? null : $n;
    }

    /**
     * Accept a plausible image link only. http(s) absolute, protocol-relative
     * (//host/…) or root-relative (/storage/…) URLs pass; anything else (bare
     * text, javascript:, data:, spreadsheet formulas) is dropped rather than
     * stored and later rendered as an <img src> on the public menu.
     */
    private function parseUrl(?string $v): ?string
    {
        if ($v === null) {
            return null;
        }
        $v = $this->clip($v, self::MAX_URL);
        if (! preg_match('#^(https?://|//|/)#i', $v)) {
            return null;
        }

        return $v;
    }

    private function parseBool(?string $v, bool $default): bool
    {
        if ($v === null) {
            return $default;
        }
        $v = mb_strtolower(trim($v));

        if (in_array($v, ['1', 'true', 'yes', 'y', 'available', 'نعم', 'متاح', 'مميز'], true)) {
            return true;
        }
        if (in_array($v, ['0', 'false', 'no', 'n', 'unavailable', 'لا', 'غير متاح'], true)) {
            return false;
        }

        return $default;
    }

    private function hasAny(array $header, array $keys): bool
    {
        foreach ($keys as $k) {
            if (isset($header[$k])) {
                return true;
            }
        }

        return false;
    }
}
