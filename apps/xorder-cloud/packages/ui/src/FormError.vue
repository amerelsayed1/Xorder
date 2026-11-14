<script setup>
defineProps({ errors: { type: Object, default: () => ({}) }, field: { type: String, required: true } })
</script>

<!--
    `data-field-error` is what `focusFirstError` finds. Tagging the message
    rather than the input is deliberate: forms here label with `<span class="label">`
    and carry no `name` attributes, so the message is the only element in the
    DOM that knows which field it belongs to.
-->
<template>
    <p v-if="errors[field]" :data-field-error="field" class="text-xs text-red-600 mt-1">{{ errors[field][0] }}</p>
</template>
