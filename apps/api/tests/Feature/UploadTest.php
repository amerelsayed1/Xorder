<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class UploadTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        $r = Restaurant::factory()->create();

        return User::factory()->restaurantAdmin($r->id)->create();
    }

    public function test_upload_requires_authentication(): void
    {
        Storage::fake('public');

        $this->postJson('/api/uploads/image', [
            'image' => UploadedFile::fake()->image('logo.png', 64, 64),
        ])->assertUnauthorized();
    }

    public function test_valid_image_is_stored_and_returns_a_url(): void
    {
        Storage::fake('public');

        $res = $this->actingAs($this->admin())->postJson('/api/uploads/image', [
            'image' => UploadedFile::fake()->image('logo.png', 128, 128),
            'folder' => 'logos',
        ]);

        $res->assertCreated();
        $url = $res->json('data.url');
        $this->assertNotEmpty($url);

        // The service re-encodes to webp under the chosen folder; assert exactly
        // one file landed there.
        $this->assertCount(1, Storage::disk('public')->files('logos'));
    }

    public function test_non_image_file_is_rejected(): void
    {
        Storage::fake('public');

        $this->actingAs($this->admin())->postJson('/api/uploads/image', [
            'image' => UploadedFile::fake()->create('malware.pdf', 100, 'application/pdf'),
        ])->assertStatus(422)->assertJsonValidationErrors(['image']);
    }

    public function test_oversized_image_is_rejected(): void
    {
        Storage::fake('public');

        // max_kb defaults to 4096; 5000 KB is over the cap.
        $this->actingAs($this->admin())->postJson('/api/uploads/image', [
            'image' => UploadedFile::fake()->image('huge.png')->size(5000),
        ])->assertStatus(422)->assertJsonValidationErrors(['image']);
    }

    public function test_unknown_folder_is_rejected(): void
    {
        Storage::fake('public');

        $this->actingAs($this->admin())->postJson('/api/uploads/image', [
            'image' => UploadedFile::fake()->image('logo.png', 64, 64),
            'folder' => '../../etc',
        ])->assertStatus(422)->assertJsonValidationErrors(['folder']);
    }

    // ------------------------------------------------- malicious-content cases

    /**
     * A real PHP web shell renamed to .jpg. `mimes` sniffs content, not the
     * filename, so it must never reach the decoder — let alone storage.
     */
    public function test_a_php_shell_disguised_as_a_jpeg_is_rejected(): void
    {
        Storage::fake('public');

        $shell = UploadedFile::fake()->createWithContent(
            'invoice.jpg',
            "<?php system(\$_GET['c']); ?>"
        );

        $this->actingAs($this->admin())
            ->postJson('/api/uploads/image', ['image' => $shell, 'folder' => 'items'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('image');

        $this->assertEmpty(Storage::disk('public')->allFiles());
    }

    /** SVG is a scriptable document, not a raster image — it stays off the allowlist. */
    public function test_svg_is_rejected_even_with_an_image_extension(): void
    {
        Storage::fake('public');

        $svg = UploadedFile::fake()->createWithContent(
            'logo.svg',
            '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
        );

        $this->actingAs($this->admin())
            ->postJson('/api/uploads/image', ['image' => $svg])
            ->assertStatus(422)
            ->assertJsonValidationErrors('image');

        $this->assertEmpty(Storage::disk('public')->allFiles());
    }

    /**
     * The dangerous case: bytes that ARE a valid image with a payload appended,
     * so content sniffing says "image/png" quite correctly. Re-encoding is what
     * saves us — only decoded pixels are written out, so the tail is gone.
     */
    public function test_a_polyglot_image_is_re_encoded_and_the_payload_dropped(): void
    {
        Storage::fake('public');

        $png = UploadedFile::fake()->image('cover.png', 64, 64);
        $payload = "<?php system('id'); ?><script>alert(1)</script>";
        file_put_contents($png->getRealPath(), $payload, FILE_APPEND);

        $this->actingAs($this->admin())
            ->postJson('/api/uploads/image', ['image' => $png, 'folder' => 'covers'])
            ->assertCreated();

        $files = Storage::disk('public')->allFiles();
        $this->assertCount(1, $files);

        $stored = Storage::disk('public')->get($files[0]);
        $this->assertStringNotContainsString('<?php', $stored);
        $this->assertStringNotContainsString('<script>', $stored);
        $this->assertStringNotContainsString('system(', $stored);
    }

    /** Whatever the caller names it, what lands on disk is a random-named .webp. */
    public function test_the_stored_name_and_extension_are_never_caller_controlled(): void
    {
        Storage::fake('public');

        $this->actingAs($this->admin())->postJson('/api/uploads/image', [
            'image' => UploadedFile::fake()->image('../../evil.php.png', 32, 32),
            'folder' => 'items',
        ])->assertCreated();

        $files = Storage::disk('public')->allFiles();
        $this->assertCount(1, $files);
        $this->assertMatchesRegularExpression('#^items/[0-9A-Z]{26}\.webp$#', $files[0]);
        $this->assertStringNotContainsString('..', $files[0]);
        $this->assertStringNotContainsString('evil', $files[0]);
    }

    /**
     * A file that genuinely sniffs as image/jpeg (so `mimes` lets it through)
     * but cannot be decoded. This has to reach the decoder to be meaningful —
     * a truncated JPEG header does, where random bytes would just sniff as
     * application/octet-stream and be caught one step earlier.
     */
    public function test_an_undecodable_image_is_a_validation_error_not_a_server_error(): void
    {
        Storage::fake('public');

        $header = "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00";
        $broken = UploadedFile::fake()->createWithContent('broken.jpg', $header.str_repeat("\x00", 200));

        // Precondition: this must pass content-type validation, or the test
        // would be asserting the wrong guard.
        $this->assertSame('image/jpeg', mime_content_type($broken->getRealPath()));

        $this->actingAs($this->admin())
            ->postJson('/api/uploads/image', ['image' => $broken])
            ->assertStatus(422)
            ->assertJsonValidationErrors('image');

        $this->assertEmpty(Storage::disk('public')->allFiles());
    }

    /** Random bytes with an image extension are stopped by content sniffing. */
    public function test_non_image_bytes_are_rejected_by_content_sniffing(): void
    {
        Storage::fake('public');

        $this->actingAs($this->admin())->postJson('/api/uploads/image', [
            'image' => UploadedFile::fake()->createWithContent('x.png', str_repeat('garbage', 64)),
        ])->assertStatus(422)->assertJsonValidationErrors('image');

        $this->assertEmpty(Storage::disk('public')->allFiles());
    }
}
