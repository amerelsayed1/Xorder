<script setup>
defineProps({
    isOpen: Boolean,
    reopenUrl: String,
    orderCode: String,
    t: Function,
})

defineEmits(['close'])
</script>

<template>
    <Teleport to="body">
        <div v-if="isOpen" class="modal-backdrop cart-dialog-backdrop" @click.self="$emit('close')">
            <div class="simple-dialog" role="dialog" aria-modal="true" style="text-align:center">
                <div class="success-circle">✓</div>
                <h2>{{ t('order_sent') }}</h2>
                <p v-if="orderCode" style="color:var(--muted);font-weight:700;font-size:13px;margin:0 0 6px" dir="ltr">{{ t('order_ref') }}: {{ orderCode }}</p>
                <p style="color:var(--muted);font-size:13px;line-height:1.8;margin:0">
                    {{ t('order_sent_hint') }}
                    <a v-if="reopenUrl" :href="reopenUrl" target="_blank" rel="noopener" style="color:var(--accent-dark);font-weight:700">{{ t('reopen_wa') }}</a>
                </p>
                <button class="dialog-button" @click="$emit('close')">{{ t('close') }}</button>
            </div>
        </div>
    </Teleport>
</template>
