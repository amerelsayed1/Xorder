<script setup>
defineProps({ errors: { type: Object, default: () => ({}) }, field: { type: String, required: true } })
</script>

<template>
    <p v-if="errors[field]" class="text-xs text-red-600 mt-1">{{ errors[field][0] }}</p>
</template>
