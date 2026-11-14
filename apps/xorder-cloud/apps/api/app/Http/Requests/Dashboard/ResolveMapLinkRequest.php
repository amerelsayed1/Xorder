<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

class ResolveMapLinkRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isTenantUser() ?? false;
    }

    public function rules(): array
    {
        return [
            // Accepts a Google Maps URL, a share short link, or a raw "lat,lng".
            'url' => ['required', 'string', 'max:2048'],
        ];
    }
}
