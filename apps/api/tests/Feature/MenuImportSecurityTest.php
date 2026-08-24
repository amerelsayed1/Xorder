<?php

namespace Tests\Feature;

use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * The import accepts a spreadsheet — a far richer file format than an image —
 * so it gets its own hostile-input coverage: XML entity expansion, formulas,
 * script-bearing cells, and parser selection.
 */
class MenuImportSecurityTest extends TestCase
{
    use RefreshDatabase;

    private const HEADER = 'category_en,category_ar,name_en,name_ar,description_en,description_ar,price,discounted_price,available,featured,image_url';

    private function admin(): User
    {
        $r = Restaurant::factory()->create(['bilingual' => true]);

        return User::factory()->restaurantAdmin($r->id)->create();
    }

    private function upload(User $admin, UploadedFile $file): TestResponse
    {
        return $this->actingAs($admin)->postJson('/api/dashboard/items/import', ['file' => $file]);
    }

    private function csv(User $admin, string $body): TestResponse
    {
        return $this->upload($admin, UploadedFile::fake()->createWithContent(
            'menu.csv', "\xEF\xBB\xBF".self::HEADER."\n".$body
        ));
    }

    /**
     * An XLSX is a zip of XML. A workbook declaring an external entity must not
     * cause a file read — PhpSpreadsheet's scanner should refuse it, and we
     * answer 422 rather than leaking a parser stack trace.
     */
    public function test_an_xlsx_declaring_external_entities_is_refused(): void
    {
        $xxe = <<<'XML'
        <?xml version="1.0"?>
        <!DOCTYPE foo [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
        <workbook><sheet>&xxe;</sheet></workbook>
        XML;

        $zip = tempnam(sys_get_temp_dir(), 'xlsx');
        $archive = new \ZipArchive;
        $archive->open($zip, \ZipArchive::OVERWRITE);
        $archive->addFromString('[Content_Types].xml', $xxe);
        $archive->addFromString('xl/workbook.xml', $xxe);
        $archive->close();

        $file = UploadedFile::fake()->createWithContent('menu.xlsx', file_get_contents($zip));
        unlink($zip);

        $res = $this->upload($this->admin(), $file);

        $this->assertContains($res->status(), [422], 'a hostile workbook must be a validation error');
        $this->assertStringNotContainsString('root:', $res->getContent());
        $this->assertSame(0, MenuItem::withoutGlobalScopes()->count());
    }

    /** A cell containing markup is stored as text — it is data, never markup. */
    public function test_script_bearing_cells_are_stored_as_inert_text(): void
    {
        $admin = $this->admin();

        $this->csv($admin, 'Drinks,مشروبات,"<script>alert(1)</script>",عصير,,,10,,yes,no,')
            ->assertOk();

        $item = MenuItem::withoutGlobalScopes()->first();
        $this->assertNotNull($item);
        $this->assertSame('<script>alert(1)</script>', $item->name_en);
    }

    /**
     * image_url lands in the DOM as an <img src>, so the importer only accepts
     * http(s)/relative — a javascript: cell must not survive the round trip.
     */
    public function test_a_javascript_image_url_cell_is_dropped(): void
    {
        $admin = $this->admin();

        $this->csv($admin, 'Drinks,مشروبات,Juice,عصير,,,10,,yes,no,javascript:alert(1)')
            ->assertOk();

        $item = MenuItem::withoutGlobalScopes()->first();
        $this->assertNotNull($item);
        $this->assertNull($item->image_url);
    }

    /** A legitimate image URL still imports. */
    public function test_a_normal_image_url_cell_survives(): void
    {
        $admin = $this->admin();

        $this->csv($admin, 'Drinks,مشروبات,Juice,عصير,,,10,,yes,no,https://cdn.test/j.webp')
            ->assertOk();

        $this->assertSame('https://cdn.test/j.webp', MenuItem::withoutGlobalScopes()->first()->image_url);
    }

    /** Executables are refused by content type, whatever the file is called. */
    public function test_a_disguised_binary_is_rejected(): void
    {
        $file = UploadedFile::fake()->createWithContent('menu.csv', "\x7fELF\x02\x01\x01".str_repeat("\x00", 300));

        $this->upload($this->admin(), $file)->assertStatus(422);
        $this->assertSame(0, MenuItem::withoutGlobalScopes()->count());
    }
}
