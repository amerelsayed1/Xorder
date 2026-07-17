<script setup>
import { ref, watch } from 'vue'

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

watch(() => props.isOpen, (open) => {
    if (open) note.value = ''
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
                        <strong>{{ money(kind === 'combo' ? item.base_price : (item.discounted_price ?? item.price)) }}</strong>
                    </div>

                    <div v-for="(group, gi) in getGroups()" :key="gi" class="options-section">
                        <div class="options-title">
                            <strong>{{ localize(group) || t('choose_options') }}</strong>
                            <span :class="{ required: kind === 'combo' || group.is_required }">
                                {{ (kind === 'combo' || group.is_required) ? t('required') : t('optional') }}
                            </span>
                        </div>
                        <label v-for="(opt, oi) in getOptions(group)" :key="oi" class="option-row">
                            <span>
                                <input
                                    :type="(group.max_select || 1) > 1 ? 'checkbox' : 'radio'"
                                    :checked="isSelected(gi, oi)"
                                    @click.prevent="$emit('toggleOption', gi, oi, group)"
                                />
                                {{ localize(opt) }}
                            </span>
                            <strong>{{ optionPrice(opt) ? `+ ${money(optionPrice(opt))}` : t('free') }}</strong>
                        </label>
                    </div>

                    <label class="item-note">
                        <span>{{ t('item_note') }}</span>
                        <textarea v-model="note" :placeholder="t('item_note_ph')"></textarea>
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
