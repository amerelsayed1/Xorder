<script setup>
import { ref, computed } from 'vue'
import { createReview } from '../api.js'
import { isValidMobile } from '../lib/phone.js'

const props = defineProps({
    isOpen: Boolean,
    slug: { type: String, required: true },
    locale: { type: String, default: 'ar' },
    sessionToken: { type: String, default: '' },
    orderId: { type: [Number, String], default: null },
    publicReviewUrl: { type: String, default: '' },
    thankYou: { type: String, default: '' },
    customerName: { type: String, default: '' },
    customerPhone: { type: String, default: '' },
    t: { type: Function, required: true },
})

const emit = defineEmits(['close', 'submitted'])

const rating = ref(0)
const hover = ref(0)
const comment = ref('')
// The customer already gave their name/phone when ordering — reuse it and
// hide those fields instead of asking again.
const name = ref(props.customerName || '')
const phone = ref(props.customerPhone || '')
const isRtl = computed(() => props.locale === 'ar')
const contactOk = ref(false)
const submitting = ref(false)
const done = ref(false)
const errorMsg = ref('')
const serverThankYou = ref('')
const serverPublicUrl = ref('')

const stars = [1, 2, 3, 4, 5]
const thanksText = computed(() => serverThankYou.value || props.thankYou || props.t('review_thanks'))
const publicUrl = computed(() => serverPublicUrl.value || props.publicReviewUrl || '')

function setRating(n) {
    rating.value = n
    errorMsg.value = ''
}

async function submit() {
    if (submitting.value) return
    if (rating.value < 1) {
        errorMsg.value = props.t('review_rating_required')
        return
    }
    // Phone is optional here, but if given it must be a valid number.
    if (phone.value && !isValidMobile(phone.value)) {
        errorMsg.value = props.t('f_phone_required')
        return
    }
    submitting.value = true
    errorMsg.value = ''
    try {
        const res = await createReview(props.slug, {
            rating: rating.value,
            comment: comment.value || undefined,
            customer_name: name.value || undefined,
            customer_phone: phone.value || undefined,
            contact_permission: contactOk.value,
            session_token: props.sessionToken || undefined,
            order_id: props.orderId || undefined,
        }, props.locale)
        serverThankYou.value = res?.data?.thank_you || ''
        serverPublicUrl.value = res?.data?.public_review_url || ''
        done.value = true
        emit('submitted')
    } catch (e) {
        errorMsg.value = e.response?.data?.message || props.t('review_error')
    } finally {
        submitting.value = false
    }
}
</script>

<template>
    <Teleport to="body">
        <div v-if="isOpen" class="modal-backdrop cart-dialog-backdrop" @click.self="emit('close')">
            <div class="simple-dialog" role="dialog" aria-modal="true" :dir="isRtl ? 'rtl' : 'ltr'">
                <button class="modal-close" type="button" @click="emit('close')">×</button>

                <template v-if="!done">
                    <h2>{{ t('review_title') }}</h2>
                    <p class="rev-hint">{{ t('review_private_hint') }}</p>

                    <div class="rev-stars" @mouseleave="hover = 0">
                        <button
                            v-for="s in stars"
                            :key="s"
                            type="button"
                            class="rev-star"
                            :class="{ 'rev-star--on': s <= (hover || rating) }"
                            :aria-label="`${s}`"
                            @mouseenter="hover = s"
                            @click="setRating(s)"
                        >★</button>
                    </div>

                    <textarea
                        v-model="comment"
                        class="rev-input rev-textarea"
                        rows="2"
                        :placeholder="t('review_comment_ph')"
                    />
                    <input v-if="!customerName" v-model="name" class="rev-input" type="text" :placeholder="t('review_name_ph')" />
                    <input v-if="!customerPhone" v-model="phone" class="rev-input" type="tel" dir="ltr" :style="{ textAlign: isRtl ? 'right' : 'left' }" :placeholder="t('review_phone_ph')" />

                    <label class="rev-check">
                        <input v-model="contactOk" type="checkbox" />
                        <span>{{ t('review_contact_ok') }}</span>
                    </label>

                    <p v-if="errorMsg" class="rev-error">{{ errorMsg }}</p>

                    <button
                        class="dialog-button bill-primary"
                        type="button"
                        :disabled="submitting"
                        @click="submit"
                    >
                        {{ submitting ? t('review_sending') : t('review_submit') }}
                    </button>
                    <button class="dialog-button" type="button" @click="emit('close')">
                        {{ t('review_skip') }}
                    </button>
                </template>

                <template v-else>
                    <div class="success-circle">✓</div>
                    <h2>{{ t('review_thanks_title') }}</h2>
                    <p class="rev-hint">{{ thanksText }}</p>
                    <a
                        v-if="publicUrl"
                        :href="publicUrl"
                        target="_blank"
                        rel="noopener"
                        class="dialog-button bill-primary rev-public"
                    >{{ t('review_public_cta') }}</a>
                    <button class="dialog-button" type="button" @click="emit('close')">
                        {{ t('close') }}
                    </button>
                </template>
            </div>
        </div>
    </Teleport>
</template>

<style scoped>
.rev-hint { color: var(--muted); font-size: 13px; line-height: 1.7; margin: 0 0 14px; }
.rev-stars { display: flex; justify-content: center; gap: 6px; margin: 4px 0 16px; }
.rev-star {
    background: none; border: 0; cursor: pointer; font-size: 34px; line-height: 1;
    color: var(--line); padding: 0; transition: color .12s ease, transform .12s ease;
}
.rev-star--on { color: #f5b301; }
.rev-star:hover { transform: scale(1.1); }
.rev-input {
    width: 100%; border: 1px solid var(--line); border-radius: 12px;
    padding: 10px 12px; font: inherit; margin-bottom: 10px; box-sizing: border-box;
}
.rev-textarea { resize: none; }
.rev-check {
    display: flex; align-items: center; gap: 8px; font-size: 13px;
    color: var(--body); margin: 2px 0 6px; cursor: pointer; text-align: start;
}
.rev-check input { width: 16px; height: 16px; flex: none; }
.rev-error { color: #b42318; font-size: 13px; margin: 8px 0 0; }
.rev-public { display: block; text-decoration: none; text-align: center; }
</style>
