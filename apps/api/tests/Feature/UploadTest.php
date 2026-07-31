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
}
