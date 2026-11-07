<script setup>
defineProps({
    isOpen: Boolean,
    reopenUrl: String,
    orderCode: String,
    viaWhatsapp: { type: Boolean, default: true },
    // Set when the order was refused or did not arrive (XORD-047): the server's
    // reason, shown in place of the success message.
    errorMessage: { type: String, default: '' },
    t: Function,
})

defineEmits(['close'])
</script>

<template>
    <Teleport to="body">
        <div v-if="isOpen" class="modal-backdrop cart-dialog-backdrop" @click.self="$emit('close')">
            <div class="simple-dialog" role="dialog" aria-modal="true" style="text-align:center">
                <template v-if="errorMessage">
                    <h2>{{ t('order_not_placed') }}</h2>
                    <p style="color:var(--muted);font-size:13px;line-height:1.8;margin:0 0 6px">{{ errorMessage }}</p>
                    <p style="color:var(--muted);font-size:13px;line-height:1.8;margin:0">{{ t('order_not_placed_hint') }}</p>
                    <button class="dialog-button" @click="$emit('close')">{{ t('close') }}</button>
                </template>
                <template v-else>
                <div class="success-circle">✓</div>
                <h2>{{ viaWhatsapp ? t('order_sent') : t('order_received') }}</h2>
                <p v-if="orderCode" style="color:var(--muted);font-weight:700;font-size:13px;margin:0 0 6px" dir="ltr">{{ t('order_ref') }}: {{ orderCode }}</p>
                <p style="color:var(--muted);font-size:13px;line-height:1.8;margin:0">
                    <template v-if="viaWhatsapp">
                        {{ t('order_sent_hint') }}
                        <a v-if="reopenUrl" :href="reopenUrl" target="_blank" rel="noopener" style="color:var(--accent-dark);font-weight:700">{{ t('reopen_wa') }}</a>
                    </template>
                    <template v-else>{{ t('order_received_hint') }}</template>
                </p>
                <button class="dialog-button" @click="$emit('close')">{{ t('close') }}</button>
                </template>
            </div>
        </div>
    </Teleport>
</template>
