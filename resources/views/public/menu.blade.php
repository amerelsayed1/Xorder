@php
    use App\Support\Localize;

    $lang = request('lang', $restaurant->default_language->value);
    $lang = in_array($lang, ['ar', 'en'], true) ? $lang : 'en';
    $dir = $lang === 'ar' ? 'rtl' : 'ltr';
    $isAr = $lang === 'ar';

    $rName = Localize::pick($restaurant->name_ar, $restaurant->name_en, $lang);
    $rDesc = Localize::pick($restaurant->description_ar, $restaurant->description_en, $lang);
    $altName = $isAr ? $restaurant->name_en : $restaurant->name_ar;
    $brand = $restaurant->brand_color ?: '#b8431f';
    $initial = mb_substr(trim((string) ($rName ?: 'M')), 0, 1);
    $waDigits = preg_replace('/[^0-9]/', '', (string) $restaurant->whatsapp_number);

    $t = [
        'wa'        => $isAr ? 'واتساب' : 'WhatsApp',
        'search'    => $isAr ? 'ابحث في القائمة…' : 'Search the menu…',
        'featured'  => $isAr ? 'مميّز' : 'Featured',
        'na'        => $isAr ? 'غير متاح' : 'Unavailable',
        'none'      => $isAr ? 'لا توجد نتائج' : 'Nothing found',
        'items'     => $isAr ? 'صنف' : 'items',
        'visit'     => $isAr ? 'زورونا' : 'Visit',
        'contact'   => $isAr ? 'تواصل' : 'Contact',
        'hours'     => $isAr ? 'ساعات العمل' : 'Hours',
        'wa_cta'    => $isAr ? 'تواصل عبر واتساب' : 'Message us on WhatsApp',
    ];
    $num = fn ($v) => Localize::digits($v, $lang);
@endphp
<!DOCTYPE html>
<html lang="{{ $lang }}" dir="{{ $dir }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ $rName }}{{ $rDesc ? ' — ' . \Illuminate\Support\Str::limit($rDesc, 50) : '' }}</title>
    <meta name="description" content="{{ \Illuminate\Support\Str::limit(strip_tags((string) $rDesc), 160) }}">
    <link rel="canonical" href="{{ $restaurant->publicUrl() }}">
    <meta property="og:type" content="restaurant.menu">
    <meta property="og:title" content="{{ $rName }}">
    <meta property="og:description" content="{{ \Illuminate\Support\Str::limit(strip_tags((string) $rDesc), 160) }}">
    @if ($restaurant->cover_image_url)<meta property="og:image" content="{{ $restaurant->cover_image_url }}">@endif

    <script type="application/ld+json">
    {!! json_encode(['@context' => 'https://schema.org', '@type' => 'Restaurant', 'name' => $rName,
        'description' => $rDesc, 'image' => $restaurant->cover_image_url ?: $restaurant->logo_url,
        'address' => $restaurant->address, 'telephone' => $restaurant->phone, 'url' => $restaurant->publicUrl()],
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) !!}
    </script>

    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=DM+Serif+Display&family=Amiri:wght@400;700&family=Space+Grotesk:wght@400;500;600;700&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Sans+Arabic:wght@400;500;600&family=IBM+Plex+Mono&display=swap" rel="stylesheet">
    @vite(['resources/css/public.css'])
    <style>:root { --accent: {{ $brand }}; }</style>
</head>
<body>

    {{-- Header --}}
    <header class="hdr">
        <div class="hdr-in">
            <a href="?lang={{ $lang }}" class="brand">
                @if ($restaurant->logo_url)
                    <img src="{{ $restaurant->logo_url }}" alt="" class="brand-mark" style="object-fit:cover">
                @else
                    <span class="brand-mark">{{ $initial }}</span>
                @endif
                <span>
                    <span class="brand-nm">{{ $rName }}</span>
                    @if ($altName)<span class="brand-tag">{{ $altName }}</span>@endif
                </span>
            </a>
            <div class="hdr-actions">
                <span class="lang">
                    <a href="?lang=en" class="{{ ! $isAr ? 'on' : '' }}">EN</a>
                    <a href="?lang=ar" class="{{ $isAr ? 'on' : '' }}">ع</a>
                </span>
                @if ($waDigits)
                    <a href="https://wa.me/{{ $waDigits }}" target="_blank" rel="noopener" class="wa">✆ {{ $t['wa'] }}</a>
                @endif
            </div>
        </div>
    </header>

    {{-- Hero --}}
    <section class="hero">
        @if ($restaurant->cover_image_url)
            <img src="{{ $restaurant->cover_image_url }}" alt="">
        @endif
        <div class="hero-ov"></div>
        <div class="hero-c">
            <div class="hero-in">
                <h1 class="hero-nm">{{ $rName }}</h1>
                <div class="hero-meta">
                    @if ($restaurant->opening_hours)
                        <span class="chip"><span class="gdot"></span>{{ $restaurant->opening_hours }}</span>
                    @endif
                    @if ($restaurant->address)<span class="chip">⚲ {{ $restaurant->address }}</span>@endif
                    @if ($restaurant->phone)<span class="chip">✆ {{ $num($restaurant->phone) }}</span>@endif
                </div>
            </div>
        </div>
    </section>

    {{-- Sub-nav --}}
    <nav class="subnav">
        <div class="subnav-in">
            <div class="cats">
                @foreach ($categories as $i => $category)
                    <a href="#cat-{{ $category->id }}" class="catchip {{ $i === 0 ? 'on' : '' }}" data-chip="{{ $category->id }}">
                        {{ Localize::pick($category->name_ar, $category->name_en, $lang) }}
                    </a>
                @endforeach
            </div>
            <div class="search">
                <span class="ic">⌕</span>
                <input type="search" placeholder="{{ $t['search'] }}" oninput="filterMenu(this.value)">
            </div>
        </div>
    </nav>

    <main>
        @foreach ($categories as $category)
            @php
                $cName = Localize::pick($category->name_ar, $category->name_en, $lang);
                $cAlt = $isAr ? $category->name_en : $category->name_ar;
            @endphp
            <section class="section" id="cat-{{ $category->id }}" data-category>
                <div class="sec-head">
                    <h2 class="sec-title">{{ $cName }}</h2>
                    @if ($cAlt)<span class="sec-alt">{{ $cAlt }}</span>@endif
                    <span class="sec-count">{{ $num($category->menuItems->count()) }} {{ $t['items'] }}</span>
                </div>
                <div class="grid">
                    @foreach ($category->menuItems as $item)
                        @include('public.partials.item-card', ['item' => $item, 'lang' => $lang, 'isAr' => $isAr, 't' => $t, 'num' => $num])
                    @endforeach
                </div>
            </section>
        @endforeach
        <p id="no-results" class="empty" style="display:none">{{ $t['none'] }}</p>
    </main>

    {{-- Footer --}}
    <footer class="ftr">
        <div class="ftr-in">
            <div>
                <div class="ftr-brand-nm">{{ $rName }}</div>
                @if ($rDesc)<p>{{ $rDesc }}</p>@endif
                @if ($waDigits)
                    <a href="https://wa.me/{{ $waDigits }}" target="_blank" rel="noopener" class="ftr-wa">✆ {{ $t['wa_cta'] }}</a>
                @endif
            </div>
            <div>
                <h4>{{ $t['visit'] }}</h4>
                @if ($restaurant->address)<p>{{ $restaurant->address }}</p>@endif
                @if ($restaurant->opening_hours)<p style="margin-top:8px">{{ $t['hours'] }}: {{ $restaurant->opening_hours }}</p>@endif
            </div>
            <div>
                <h4>{{ $t['contact'] }}</h4>
                @if ($restaurant->phone)<p>{{ $num($restaurant->phone) }}</p>@endif
                @if ($restaurant->whatsapp_number)<p style="margin-top:8px">{{ $t['wa'] }}: {{ $num($restaurant->whatsapp_number) }}</p>@endif
            </div>
        </div>
        <div class="ftr-bot">© {{ $num(date('Y')) }} {{ $rName }}. {{ $isAr ? 'جميع الحقوق محفوظة.' : 'All rights reserved.' }}</div>
    </footer>

    <script>
        function filterMenu(q) {
            const term = (q || '').trim().toLowerCase();
            let any = false;
            document.querySelectorAll('[data-category]').forEach(sec => {
                let vis = 0;
                sec.querySelectorAll('[data-item]').forEach(row => {
                    const match = !term || (row.dataset.name || '').includes(term);
                    row.style.display = match ? '' : 'none';
                    if (match) vis++;
                });
                sec.style.display = vis ? '' : 'none';
                if (vis) any = true;
            });
            document.getElementById('no-results').style.display = any ? 'none' : '';
        }
        // Scroll-spy for category chips.
        const chips = document.querySelectorAll('[data-chip]');
        const obs = new IntersectionObserver((entries) => {
            entries.forEach(e => {
                if (e.isIntersecting) chips.forEach(c => c.classList.toggle('on', c.dataset.chip === e.target.id.replace('cat-', '')));
            });
        }, { rootMargin: '-45% 0px -50% 0px' });
        document.querySelectorAll('[data-category]').forEach(s => obs.observe(s));
    </script>
</body>
</html>
