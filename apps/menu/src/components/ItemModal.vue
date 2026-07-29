<script setup>
import { computed, nextTick, ref, watch } from 'vue'

const props = defineProps({
    isOpen: Boolean,
    item: Object,
    kind: String,
    quantity: Number,
    selectedGroups: Object,
    orderingEnabled: Boolean,
    t: Function,
    money: Function,
    localize: Function,
    isValid: Boolean,
    unitPrice: Number,
})

const emit = defineEmits(['close', 'toggleOption', 'updateQuantity', 'addToCart'])

const note = ref('')
const noteEl = ref(null)

// The notes field starts at a single practical row and grows with its content
// up to a cap (then scrolls), so it isn't a big empty box by default.
function autoGrowNote() {
    const el = noteEl.value
    if (!el) return
    el.style.height = 'auto'
    el.style.height = `${Math.min(el.scrollHeight, 132)}px`
}

watch(() => props.isOpen, (open) => {
    if (open) {
        note.value = ''
        nextTick(autoGrowNote)
    }
})

function getGroups() {
    if (!props.item) return []
    return props.kind === 'item' ? (props.item.option_groups || []) : (props.item.groups || [])
}

function getOptions(g) {
    return props.kind === 'item' ? (g.options || []) : (g.items || [])
}

function optionPrice(opt) {
    return Number(opt.price ?? opt.extra_price ?? 0)
}

function isSelected(gi, oi) {
    const s = props.selectedGroups[gi]
    return Array.isArray(s) ? s.includes(oi) : s === oi
}

// When the item has a size/portion group, its price isn't a fixed base — the
// chosen variant sets it. Show the live unit price in the header so it tracks
// the selection (before a pick it reads as the "starting from" price).
const hasVariant = computed(() => getGroups().some((g) => g.is_variant))
const headerPrice = computed(() => {
    if (hasVariant.value) return props.unitPrice
    if (props.kind === 'combo') return props.item?.base_price
    return props.item?.discounted_price ?? props.item?.price
})
</script>

<template>
    <Teleport to="body">
        <div v-if="isOpen && item" class="modal-backdrop" @click.self="$emit('close')">
            <section class="item-modal" :class="{ 'no-image': !item.image_url }" role="dialog" aria-modal="true" aria-labelledby="item-modal-title">
                <button class="modal-close" :aria-label="t('close')" @click="$emit('close')">×</button>

                <div v-if="item.image_url" class="modal-image-wrap">
                    <img v-img-fade :src="item.image_url" :alt="localize(item)" decoding="async" />
                    <span v-if="item.is_featured" class="popular-badge">{{ t('popular') }}</span>
                </div>

                <div class="modal-content">
                    <div class="modal-heading">
                        <div>
                            <h2 id="item-modal-title">{{ localize(item) }}</h2>
                            <p v-if="localize(item, 'description')">{{ localize(item, 'description') }}</p>
                        </div>
                        <strong>{{ money(headerPrice) }}</strong>
                    </div>

                    <!-- Options + prices are shown on a display-only menu too, so a
                         diner can see the choices — but on such a menu they're purely
                         informational: no selector control and no "required" badge. -->
                    <div v-for="(group, gi) in getGroups()" :key="gi" class="options-section">
                        <div class="options-title">
                            <strong>{{ localize(group) || t('choose_options') }}</strong>
                            <span v-if="orderingEnabled" :class="{ required: kind === 'combo' || group.is_required }">
                                {{ (kind === 'combo' || group.is_required) ? t('required') : t('optional') }}
                            </span>
                        </div>
                        <!-- The click handler lives on the label (not the input) so a
                             tap anywhere on the row fires exactly one toggle. A native
                             radio/checkbox inside a <label> otherwise receives both its
                             own click and the label's forwarded click, which toggled the
                             selection on then straight back off. The input is now purely
                             a visual indicator driven by :checked. -->
                        <label
                            v-for="(opt, oi) in getOptions(group)"
                            :key="oi"
                            class="option-row"
                            :class="{ 'option-row--readonly': !orderingEnabled }"
                            @click.prevent="orderingEnabled && $emit('toggleOption', gi, oi, group)"
                        >
                            <span>
                                <input
                                    v-if="orderingEnabled"
                                    :type="(group.max_select || 1) > 1 ? 'checkbox' : 'radio'"
                                    :checked="isSelected(gi, oi)"
                                    tabindex="-1"
                                    style="pointer-events:none"
                                    @click.prevent
                                />
                                {{ localize(opt) }}
                            </span>
                            <strong v-if="group.is_variant">{{ money(optionPrice(opt)) }}</strong>
                            <strong v-else>{{ optionPrice(opt) ? `+ ${money(optionPrice(opt))}` : t('free') }}</strong>
                        </label>
                    </div>

                    <label v-if="orderingEnabled" class="item-note">
                        <span>{{ t('item_note') }}</span>
                        <textarea ref="noteEl" v-model="note" rows="1" :placeholder="t('item_note_ph')" @input="autoGrowNote"></textarea>
                    </label>

                    <div v-if="orderingEnabled" class="modal-footer">
                        <div class="quantity-control large">
                            <button :aria-label="t('remove')" @click="$emit('updateQuantity', Math.max(1, quantity - 1))">−</button>
                            <strong>{{ quantity }}</strong>
                            <button :aria-label="t('add')" @click="$emit('updateQuantity', quantity + 1)">+</button>
                        </div>
                        <button class="modal-add" :disabled="!isValid" @click="$emit('addToCart', note)">
                            {{ t('add_to_cart') }}
                            <strong>{{ money(unitPrice * quantity) }}</strong>
                        </button>
                    </div>
                </div>
            </section>
        </div>
    </Teleport>
</template>
