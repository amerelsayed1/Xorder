<script setup>
import { RouterView } from 'vue-router'
import ConfirmDialog from '@xorder/ui/ConfirmDialog.vue'
import AlertDialog from '@xorder/ui/AlertDialog.vue'
</script>

<template>
    <RouterView />
    <ConfirmDialog />
    <AlertDialog />
</template>
