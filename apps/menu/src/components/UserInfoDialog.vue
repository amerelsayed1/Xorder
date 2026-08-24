<script setup>
import { computed, nextTick, onUnmounted, ref, watch } from 'vue'
import { isValidMobile } from '../lib/phone.js'
import { isValidEmail } from '../lib/email.js'

const props = defineProps({
    isOpen: Boolean,
    isEditing: Boolean,
    userInfo: Object,
    editForm: Object,
    saveSuccess: Boolean,
    hasUserInfo: Boolean,
    initials: String,
    accent: String,
    t: Function,
})

const emit = defineEmits(['close', 'enterEdit', 'cancelEdit', 'save', 'clear', 'updateField'])

// Accessibility: close on Escape and move focus into the dialog when it opens,
// matching the other menu modals (ItemModal etc.).
const panel = ref(null)
function onKeydown(e) { if (e.key === 'Escape') emit('close') }
// Immediate: the dialog is code-split and mounts already open, so the prop
// never flips from false and a lazy watcher would miss the first open.
watch(() => props.isOpen, (open) => {
    if (open) {
        window.addEventListener('keydown', onKeydown)
        nextTick(() => panel.value?.focus())
    } else {
        window.removeEventListener('keydown', onKeydown)
    }
}, { immediate: true })
onUnmounted(() => window.removeEventListener('keydown', onKeydown))

// Only scold the customer once they try to save, not while they're still typing.
const attempted = ref(false)
const phoneInvalid = computed(() => !isValidMobile(props.editForm?.phone))
// Email is optional; only flag it when something was typed and it's malformed.
const emailInvalid = computed(() => !isValidEmail(props.editForm?.email))
watch(() => props.isEditing, () => { attempted.value = false })

function attemptSave() {
    attempted.value = true
    if (phoneInvalid.value || emailInvalid.value) return
    emit('save')
}
</script>

<template>
    <Teleport to="body">
        <div v-if="isOpen" class="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
            <div class="absolute inset-0 bg-black/50" @click="$emit('close')"></div>
            <div ref="panel" tabindex="-1" role="dialog" aria-modal="true" aria-labelledby="userinfo-title" class="relative bg-white w-full sm:max-w-md sm:rounded-3xl rounded-t-3xl max-h-[92vh] overflow-y-auto shadow-2xl focus:outline-none">
                <div class="sticky top-0 bg-white border-b border-stone-200/70 px-5 py-4 flex items-center justify-between">
                    <h2 id="userinfo-title" class="font-bold text-lg">{{ t('your_details') }}</h2>
                    <button class="text-2xl text-stone-400" :aria-label="t('close')" @click="$emit('close')">×</button>
                </div>
                <div class="p-5">
                    <template v-if="!isEditing">
                        <div v-if="hasUserInfo" class="flex items-center gap-4 mb-6">
                            <div class="h-16 w-16 rounded-full grid place-items-center text-white font-bold text-xl" :style="{ background: accent }">{{ initials }}</div>
                            <div class="flex-1">
                                <p class="text-sm text-stone-500">{{ t('f_name') }}</p>
                                <p class="font-bold text-lg">{{ userInfo.name }}</p>
                            </div>
                        </div>
                        <div v-else class="text-center py-8 text-stone-400 mb-4">
                            <div class="h-20 w-20 rounded-full mx-auto mb-3 text-4xl">👤</div>
                        </div>
                        <div class="space-y-4">
                            <div v-if="userInfo.phone">
                                <p class="text-xs text-stone-500 uppercase font-semibold">{{ t('f_phone') }}</p>
                                <p class="text-base font-semibold" dir="ltr">{{ userInfo.phone }}</p>
                            </div>
                            <div v-if="userInfo.email">
                                <p class="text-xs text-stone-500 uppercase font-semibold">{{ t('f_email') }}</p>
                                <p class="text-base font-semibold" dir="ltr">{{ userInfo.email }}</p>
                            </div>
                            <div v-if="userInfo.address">
                                <p class="text-xs text-stone-500 uppercase font-semibold">{{ t('f_address') }}</p>
                                <p class="text-sm">{{ userInfo.address }}</p>
                            </div>
                            <div v-if="userInfo.notes">
                                <p class="text-xs text-stone-500 uppercase font-semibold">{{ t('f_note') }}</p>
                                <p class="text-sm">{{ userInfo.notes }}</p>
                            </div>
                        </div>
                    </template>
                    <template v-else>
                        <div class="space-y-4">
                            <div>
                                <label class="block text-sm font-semibold mb-1.5">{{ t('f_name') }} <span class="text-red-500">*</span></label>
                                <input :value="editForm.name" type="text" class="w-full px-3.5 py-2.5 rounded-xl border border-stone-200 focus:outline-none" @input="$emit('updateField', 'name', $event.target.value)" />
                            </div>
                            <div>
                                <label class="block text-sm font-semibold mb-1.5">{{ t('f_phone') }} <span class="text-red-500">*</span></label>
                                <input :value="editForm.phone" type="tel" class="w-full px-3.5 py-2.5 rounded-xl border focus:outline-none ltr" :class="attempted && phoneInvalid ? 'border-red-400' : 'border-stone-200'" dir="ltr" :aria-invalid="attempted && phoneInvalid" @input="$emit('updateField', 'phone', $event.target.value)" />
                                <p v-if="attempted && phoneInvalid" class="text-xs text-red-500 mt-1">{{ t('f_phone_required') }}</p>
                            </div>
                            <div>
                                <label class="block text-sm font-semibold mb-1.5">{{ t('f_email') }}</label>
                                <input :value="editForm.email" type="email" class="w-full px-3.5 py-2.5 rounded-xl border focus:outline-none ltr" :class="attempted && emailInvalid ? 'border-red-400' : 'border-stone-200'" dir="ltr" :aria-invalid="attempted && emailInvalid" @input="$emit('updateField', 'email', $event.target.value)" />
                                <p v-if="attempted && emailInvalid" class="text-xs text-red-500 mt-1">{{ t('f_email_invalid') }}</p>
                            </div>
                            <div>
                                <label class="block text-sm font-semibold mb-1.5">{{ t('f_address') }} <span class="text-red-500">*</span></label>
                                <textarea :value="editForm.address" rows="2" class="w-full px-3.5 py-2.5 rounded-xl border border-stone-200 focus:outline-none resize-none" @input="$emit('updateField', 'address', $event.target.value)"></textarea>
                            </div>
                            <div>
                                <label class="block text-sm font-semibold mb-1.5">{{ t('f_note') }}</label>
                                <textarea :value="editForm.notes" rows="2" class="w-full px-3.5 py-2.5 rounded-xl border border-stone-200 focus:outline-none resize-none" @input="$emit('updateField', 'notes', $event.target.value)"></textarea>
                            </div>
                        </div>
                    </template>
                </div>
                <div class="sticky bottom-0 bg-white border-t border-stone-200/70 p-5 space-y-2">
                    <div v-if="saveSuccess" class="text-sm text-green-600 text-center font-semibold mb-2">✓ {{ t('saved') }}</div>
                    <template v-if="!isEditing">
                        <button class="w-full h-12 rounded-xl text-white font-bold" :style="{ background: accent }" @click="$emit('enterEdit')">✏️ {{ t('edit') }}</button>
                        <button v-if="hasUserInfo" class="w-full h-11 rounded-xl border border-red-200 bg-red-50 text-red-600 font-semibold" @click="$emit('clear')">🗑️ {{ t('clear') }}</button>
                        <button class="w-full h-11 rounded-xl border border-stone-200 bg-white text-stone-700 font-semibold" @click="$emit('close')">{{ t('close') }}</button>
                    </template>
                    <template v-else>
                        <button class="w-full h-12 rounded-xl text-white font-bold" :style="{ background: accent }" @click="attemptSave">💾 {{ t('save') }}</button>
                        <button class="w-full h-11 rounded-xl border border-stone-200 bg-white text-stone-700 font-semibold" @click="$emit('cancelEdit')">{{ t('cancel') }}</button>
                    </template>
                </div>
            </div>
        </div>
    </Teleport>
</template>
