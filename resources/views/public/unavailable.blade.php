@php
    use App\Support\Localize;
    $lang = request('lang', optional($restaurant?->default_language)->value ?? 'en');
    $lang = in_array($lang, ['ar', 'en'], true) ? $lang : 'en';
    $dir = $lang === 'ar' ? 'rtl' : 'ltr';
    $name = $restaurant ? Localize::pick($restaurant->name_ar, $restaurant->name_en, $lang) : null;
    $brand = $restaurant?->brand_color ?: '#b8431f';
    $initial = mb_substr(trim((string) ($name ?: 'M')), 0, 1);
    $msg = $lang === 'ar' ? 'هذه القائمة غير متاحة حالياً.' : 'This menu is currently unavailable.';
@endphp
<!DOCTYPE html>
<html lang="{{ $lang }}" dir="{{ $dir }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>{{ $name ?? 'Menu' }}</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=DM+Serif+Display&family=Amiri&family=IBM+Plex+Sans:wght@400;500&family=IBM+Plex+Sans+Arabic:wght@400;500&display=swap" rel="stylesheet">
    @vite(['resources/css/public.css'])
    <style>:root { --accent: {{ $brand }}; }</style>
</head>
<body style="min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;">
    <div style="text-align:center;max-width:360px;">
        @if ($restaurant?->logo_url)
            <img src="{{ $restaurant->logo_url }}" alt="" style="width:72px;height:72px;border-radius:18px;object-fit:cover;margin:0 auto 16px;">
        @else
            <span class="brand-mark" style="width:72px;height:72px;border-radius:18px;font-size:34px;margin:0 auto 16px;">{{ $initial }}</span>
        @endif
        @if ($name)<h1 class="serif" style="font-size:26px;color:var(--ink);margin-bottom:8px;">{{ $name }}</h1>@endif
        <p style="color:var(--muted);">{{ $msg }}</p>
    </div>
</body>
</html>
