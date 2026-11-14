# Image Upload Architecture - Single Source of Truth

## Overview

This document describes the refactored image upload system that provides a unified, maintainable approach to handling image uploads across the entire project.

## Problem Solved

Previously, image upload logic was duplicated across multiple components, making it difficult to:
- Fix bugs in one place (required changes in multiple locations)
- Add new features consistently
- Maintain consistent error handling and validation
- Manage CSRF token handling across different upload points

## Solution: Centralized Composable

### `useImageUpload` Composable

Located at: `packages/ui/src/composables/useImageUpload.js`

This is the **single source of truth** for all image upload operations across the project.

#### Features

- **File Upload**: Handles multipart form data submission with CSRF protection
- **URL Validation**: Validates image URLs before saving
- **Error Management**: Centralized error handling with user-friendly messages
- **Loading States**: Tracks upload progress via `uploading` ref
- **Folder Organization**: Supports multiple storage folders (logos, covers, items, categories, uploads)

#### API

```javascript
const { uploading, error, uploadFile, validateImageUrl, clearError } = useImageUpload()

// Upload a file
const url = await uploadFile(file, 'items')

// Validate a URL
const isValid = validateImageUrl(urlString)

// Clear error message
clearError()
```

## Phone Number Normalization

Implemented using Laravel Attributes (safe, non-intrusive):

### Models Updated
- `Restaurant.php`: Normalizes `phone` and `whatsapp_number` attributes
- `Branch.php`: Normalizes `phone` and `whatsapp_number` attributes

### How It Works

Using Attribute casts for safe, automatic normalization on attribute assignment:

```php
protected function phone(): Attribute
{
    return Attribute::make(
        set: fn(?string $value) => $this->normalizePhoneDigits($value),
    );
}
```

### Supported Formats
- Arabic-Indic digits: ٠-٩ → 0-9
- Persian digits: ۰-۹ → 0-9
- English digits: Already in correct format

### Why Attributes (not Events/Traits)?

✅ **Attribute Casts** (current solution):
- Run only during assignment
- Don't interfere with other operations
- Respect model mass assignment
- No global state concerns
- Clear intent and easy to debug

❌ **Event Listeners** (previously attempted):
- Run during multiple events (save, update, query)
- Can interfere with other operations
- Lead to unexpected side effects
- Harder to test

## Updated Components

### ImageUploader.vue

Now uses `useImageUpload` composable for all upload operations.

**Props:**
- `modelValue` (String): Current image URL
- `folder` (String): Storage folder (default: 'uploads')
- `label` (String): Display label

**Events:**
- `update:modelValue`: Emitted when image URL changes

**Features:**
- File upload with drag area
- URL paste input
- Image preview
- Clear button

## Backend

### ImageUploadService

Handles server-side image processing:
- Validates MIME types (jpg, jpeg, png, webp)
- Re-encodes images (strips EXIF/metadata)
- Downscales oversized images (max 2000px)
- Stores to organized folders

### UploadController

API endpoint: `POST /api/uploads/image`

**Validation:**
- Image required
- Valid MIME type
- Max 4096 KB
- Authenticated users only

## Usage Across Project

All these pages now use the unified system:

- Restaurant admin form (logo, cover image)
- Restaurant profile (logo, cover image)  
- Menu items (item image)
- Categories (category image)
- Combos (combo image)

## Benefits

1. **DRY**: Upload logic defined once
2. **Consistency**: All uploads behave identically
3. **Maintainability**: Changes propagate everywhere
4. **Safety**: Phone normalization via Attributes won't break other operations
5. **Testability**: Composable can be unit tested
6. **Scalability**: Easy to add features

## Fixed Issues

✅ **Image Upload 500 Error**: Fixed Intervention Image v4 API compatibility  
✅ **Phone Normalization**: Implemented safely using Attribute casts  
✅ **Upload Duplication**: Centralized in `useImageUpload` composable  
✅ **Restaurant Updates**: Work correctly with phone normalization
