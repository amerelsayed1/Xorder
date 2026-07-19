<script setup>
import { ref, computed, watch } from 'vue'

const props = defineProps({
    isOpen: Boolean,
    cart: Array,
    cartCount: Number,
    cartTotal: Number,
    canOrder: Boolean,
    isSubmitting: Boolean,
    orderType: String,
    orderTypes: Array,
    userInfo: Object,
    t: Function,
    money: Function,
    localize: Function,
    getLineOptions: Function,
})

const emit = defineEmits(['close', 'removeLine', 'bumpLine', 'clearCart', 'changeOrderType', 'submit'])

const step = ref(1)
const name = ref('')
const phone = ref('')
const note = ref('')
const email = ref('')
const address = ref('')

// Fresh dialog every open: back to step 1, prefill saved diner info.
watch(() => props.isOpen, (open) => {
    if (open) {
        step.value = 1
        name.value = props.userInfo?.name || ''
        phone.value = props.userInfo?.phone || ''
        email.value = props.userInfo?.email || ''
        address.value = props.userInfo?.address || ''
        note.value = ''
    }
})

// Cart emptied while the dialog is open (last line removed) → back to review.
watch(() => props.cart.length, (len) => {
    if (len === 0) step.value = 1
})

// Delivery needs an address; pickup / dine-in don't.
const needsAddress = computed(() => props.orderType === 'delivery')
const canSubmit = computed(() =>
    props.canOrder && phone.value.trim().length >= 8 && !props.isSubmitting &&
    (!needsAddress.value || address.value.trim().length >= 5)
)

const itemsText = computed(() => `${props.cartCount} ${props.cartCount === 1 ? props.t('item_count') : props.t('items_count')}`)

function submit() {
    if (!canSubmit.value) return
    emit('submit', {
        name: name.value.trim(),
        phone: phone.value.trim(),
        email: email.value.trim(),
        address: needsAddress.value ? address.value.trim() : '',
        note: note.value.trim(),
    })
}
</script>

<template>
    <Teleport to="body">
        <div v-if="isOpen" class="modal-backdrop cart-dialog-backdrop" @click.self="$emit('close')">
            <section class="cart-dialog" role="dialog" aria-modal="true" :aria-label="t('cart')">
                <button class="modal-close" :aria-label="t('close')" @click="$emit('close')">×</button>

                <aside class="cart-panel" :aria-label="t('cart')">
                    <!-- Heading -->
                    <div class="cart-heading">
                        <div v-if="step === 1">
                            <span class="cart-icon">
                                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z"/><path d="M3 6h18"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>
                            </span>
                            <h2>{{ t('cart') }}</h2>
                        </div>
                        <div v-else>
                            <button class="back-step" :aria-label="t('back_to_cart')" @click="step = 1">→</button>
                            <h2>{{ t('checkout_title') }}</h2>
                        </div>
                        <button v-if="step === 1 && cart.length" @click="$emit('clearCart')">{{ t('clear_cart') }}</button>
                    </div>

                    <!-- Progress -->
                    <div v-if="cart.length" class="checkout-progress" :aria-label="t('checkout_title')">
                        <component :is="step === 2 ? 'button' : 'div'" class="progress-step" :class="step === 1 ? 'active' : 'done'" @click="step === 2 && (step = 1)">
                            <span>{{ step === 2 ? '✓' : '1' }}</span>
                            <b>{{ t('review_cart') }}</b>
                        </component>
                        <i :class="{ filled: step === 2 }"></i>
                        <div class="progress-step" :class="{ active: step === 2 }">
                            <span>2</span>
                            <b>{{ t('order_details') }}</b>
                        </div>
                    </div>

                    <!-- Empty state -->
                    <div v-if="!cart.length" class="empty-cart">
                        <span>
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z"/><path d="M3 6h18"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>
                        </span>
                        <h3>{{ t('cart_empty_title') }}</h3>
                        <p>{{ t('cart_empty') }}</p>
                    </div>

                    <!-- Step 1: review -->
                    <template v-else-if="step === 1">
                        <div class="cart-items">
                            <div v-for="line in cart" :key="line.uid" class="cart-item">
                                <img v-if="line.ref.image_url" v-img-fade :src="line.ref.image_url" alt="" loading="lazy" decoding="async" />
                                <div v-else class="cart-thumb-fallback">◉</div>
                                <div class="cart-item-copy">
                                    <strong>{{ localize(line.ref) }}</strong>
                                    <span v-if="getLineOptions(line, localize).length">{{ getLineOptions(line, localize).join(' + ') }}</span>
                                    <span v-if="line.note">✎ {{ line.note }}</span>
                                    <b>{{ money(line.qty * line.price) }}</b>
                                </div>
                                <div class="cart-item-actions">
                                    <button class="remove-item" :aria-label="t('remove')" @click="$emit('removeLine', line.uid)">×</button>
                                    <div class="quantity-control">
                                        <button :aria-label="t('remove')" @click="$emit('bumpLine', line.uid, -1)">−</button>
                                        <strong>{{ line.qty }}</strong>
                                        <button :aria-label="t('add')" @click="$emit('bumpLine', line.uid, 1)">+</button>
                                    </div>
                                </div>
                            </div>
                        </div>
                        <div class="cart-total">
                            <span>{{ t('total') }}</span>
                            <strong>{{ money(cartTotal) }}</strong>
                        </div>
                        <div class="cart-step-action">
                            <button class="continue-button" @click="step = 2">
                                <span>{{ t('continue_checkout') }}</span>
                                <b>←</b>
                            </button>
                            <p>{{ t('review_hint') }}</p>
                        </div>
                    </template>

                    <!-- Step 2: details -->
                    <template v-else>
                        <div class="step-two-summary">
                            <div>
                                <span>{{ itemsText }}</span>
                                <button @click="step = 1">{{ t('edit_cart') }}</button>
                            </div>
                            <strong>{{ money(cartTotal) }}</strong>
                        </div>
                        <div class="checkout-form">
                            <div class="form-title">
                                <div>
                                    <span>2</span>
                                    <strong>{{ t('order_details') }}</strong>
                                </div>
                                <small>{{ t('data_safe') }}</small>
                            </div>

                            <!-- With a single order type there is nothing to choose — it's
                                 auto-selected, so we hide the selector entirely. -->
                            <div v-if="orderTypes.length > 1" class="order-type">
                                <button
                                    v-for="o in orderTypes"
                                    :key="o.value"
                                    :class="{ active: orderType === o.value }"
                                    @click="$emit('changeOrderType', o.value)"
                                >{{ o.label }}</button>
                            </div>

                            <label>
                                <span>{{ t('f_name') }}</span>
                                <input v-model="name" :placeholder="t('f_name_ph')" />
                            </label>
                            <label>
                                <span>{{ t('f_phone') }} *</span>
                                <input v-model="phone" :placeholder="t('f_phone_ph')" inputmode="tel" dir="ltr" />
                            </label>
                            <label v-if="needsAddress">
                                <span>{{ t('f_address') }} *</span>
                                <textarea v-model="address" :placeholder="t('f_address_ph')"></textarea>
                            </label>
                            <label>
                                <span>{{ t('f_email') }}</span>
                                <input v-model="email" :placeholder="t('f_email_ph')" inputmode="email" dir="ltr" />
                            </label>
                            <label>
                                <span>{{ t('f_note') }}</span>
                                <textarea v-model="note" :placeholder="t('f_note_ph')"></textarea>
                            </label>

                            <button class="whatsapp-order" :class="{ disabled: !canSubmit }" :disabled="!canSubmit" @click="submit">
                                <span>{{ isSubmitting ? t('sending') : t('order_wa') }}</span>
                                <svg viewBox="0 0 24 24" fill="currentColor" style="width:18px;height:18px"><path d="M19.05 4.91A9.82 9.82 0 0 0 12.04 2c-5.46 0-9.91 4.45-9.91 9.91 0 1.75.46 3.45 1.32 4.95L2.05 22l5.25-1.38c1.45.79 3.08 1.21 4.74 1.21h.004c5.46 0 9.91-4.45 9.91-9.91 0-2.65-1.03-5.14-2.9-7.01zm-7.01 15.24h-.003a8.2 8.2 0 0 1-4.18-1.15l-.3-.18-3.11.82.83-3.04-.2-.31a8.18 8.18 0 0 1-1.26-4.38c0-4.54 3.7-8.24 8.25-8.24 2.2 0 4.27.86 5.83 2.42a8.2 8.2 0 0 1 2.41 5.83c0 4.54-3.7 8.24-8.24 8.24zm4.52-6.16c-.25-.12-1.47-.72-1.69-.81-.23-.08-.39-.12-.56.12-.16.25-.64.81-.79.97-.14.17-.29.19-.54.06-.25-.12-1.05-.39-1.99-1.23-.74-.66-1.23-1.47-1.38-1.72-.14-.25-.01-.38.11-.5.11-.11.25-.29.37-.43.12-.14.16-.25.25-.41.08-.17.04-.31-.02-.43-.06-.12-.56-1.34-.76-1.84-.2-.48-.41-.42-.56-.43-.14-.01-.31-.01-.48-.01a.92.92 0 0 0-.66.31c-.23.25-.87.85-.87 2.07 0 1.22.89 2.4 1.01 2.56.12.17 1.75 2.67 4.23 3.74.59.26 1.05.41 1.41.52.59.19 1.13.16 1.56.1.48-.07 1.47-.6 1.67-1.18.21-.58.21-1.07.14-1.18-.06-.11-.22-.17-.47-.29z"/></svg>
                            </button>
                            <p class="whatsapp-note">{{ t('wa_note') }}</p>
                        </div>
                    </template>
                </aside>
            </section>
        </div>
    </Teleport>
</template>
