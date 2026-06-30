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
                {{ $num($hasDiscount ? $item->discounted_price : $item->price) }} <span class="item-cur">{{ $currency }}</span>
                @if ($hasDiscount)<span class="item-old">{{ $num($item->price) }} {{ $currency }}</span>@endif
            </div>
        </div>
        @if ($desc)<p class="item-desc">{{ $desc }}</p>@endif
        @if ($item->optionGroups->isNotEmpty())
            <button type="button" class="item-opts-btn" onclick="document.getElementById('dlg-{{ $item->id }}').showModal()">{{ $t['options'] }} ›</button>
        @endif
    </div>
</article>
@if ($item->optionGroups->isNotEmpty())
    <dialog id="dlg-{{ $item->id }}" class="item-dialog">
        <form method="dialog"><button class="dlg-x" aria-label="close">×</button></form>
        <h3 class="dlg-title">{{ $name }}</h3>
        @if ($desc)<p class="dlg-desc">{{ $desc }}</p>@endif
        @foreach ($item->optionGroups as $g)
            @php $gName = Localize::pick($g->name_ar, $g->name_en, $lang); @endphp
            <div class="dlg-group">
                <div class="dlg-group-head">
                    <span class="dlg-group-nm">{{ $gName }}</span>
                    @if ($g->is_required)
                        <span class="dlg-req">{{ $t['required'] }}</span>
                    @endif
                    <span class="dlg-choose">{{ $t['choose'] }} {{ $num($g->max_select) }}</span>
                </div>
                <ul class="dlg-options">
                    @foreach ($g->options->where('is_available', true) as $o)
                        @php $oName = Localize::pick($o->name_ar, $o->name_en, $lang); @endphp
                        <li><span>{{ $oName }}</span>@if ($o->price > 0)<span class="dlg-oprice">+{{ $num($o->price) }} {{ $currency }}</span>@endif</li>
                    @endforeach
                </ul>
            </div>
        @endforeach
    </dialog>
@endif
