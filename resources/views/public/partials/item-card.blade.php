@php
    use App\Support\Localize;
    $name = Localize::pick($item->name_ar, $item->name_en, $lang);
    $alt = $isAr ? $item->name_en : $item->name_ar;
    $desc = Localize::pick($item->description_ar, $item->description_en, $lang);
    $hasDiscount = $item->discounted_price !== null;
@endphp
<article data-item data-name="{{ \Illuminate\Support\Str::lower((string) $name . ' ' . $desc) }}"
    class="item {{ $item->is_available ? '' : 'na' }}">
    <div class="item-img">
        @if ($item->image_url)<img src="{{ $item->image_url }}" alt="{{ $name }}" loading="lazy">@endif
        @if ($item->is_featured || ! $item->is_available)
            <div class="ribbon">
                @if ($item->is_featured)<span class="tag tag-feat">★ {{ $t['featured'] }}</span>@endif
                @unless ($item->is_available)<span class="tag tag-na">{{ $t['na'] }}</span>@endunless
            </div>
        @endif
    </div>
    <div class="item-b">
        <div class="item-top">
            <div>
                <div class="item-nm">{{ $name }}</div>
                @if ($alt)<div class="item-alt">{{ $alt }}</div>@endif
            </div>
            <div class="item-price">
                {{ $num($hasDiscount ? $item->discounted_price : $item->price) }}
                @if ($hasDiscount)<span class="item-old">{{ $num($item->price) }}</span>@endif
            </div>
        </div>
        @if ($desc)<p class="item-desc">{{ $desc }}</p>@endif
    </div>
</article>
