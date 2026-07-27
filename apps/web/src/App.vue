<script setup>
import { RouterView } from 'vue-router'
import ConfirmDialog from '@xorder/ui/ConfirmDialog.vue'
import AlertDialog from '@xorder/ui/AlertDialog.vue'
import InstallAppButton from './components/InstallAppButton.vue'
import { isSuperAdminHost } from './lib/host.js'
</script>

<template>
    <RouterView />
    <ConfirmDialog />
    <AlertDialog />
    <!-- PWA install is offered on restaurant (tenant) subdomains only, not on
         the super-admin portal. -->
    <InstallAppButton v-if="!isSuperAdminHost" />
</template>
