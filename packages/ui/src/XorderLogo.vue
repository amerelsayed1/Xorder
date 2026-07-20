<script setup>
// XORDER brand logo (raster). Consumers size it by height with width:auto,
// so the PNG scales by its natural aspect ratio.
import fullLogo from './assets/xorder_full_logo.png'
import iconLogo from './assets/xorder_icon.png'

defineProps({
    iconOnly: { type: Boolean, default: false },
})
</script>

<template>
    <img
        :src="iconOnly ? iconLogo : fullLogo"
        alt="XORDER"
        style="display:block; width:auto; object-fit:contain;"
    />
</template>
