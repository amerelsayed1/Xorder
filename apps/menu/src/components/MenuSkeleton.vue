<script setup>
// Placeholder shown while the first menu payload loads, so diners see the
// page structure immediately instead of a lone spinner on a blank screen.
</script>

<template>
    <div class="menu-skeleton" aria-hidden="true">
        <div class="skel-hero shimmer"></div>
        <div class="skel-toolbar shimmer"></div>
        <div class="skel-section-title shimmer"></div>
        <div class="skel-grid">
            <div v-for="n in 8" :key="n" class="skel-card">
                <div class="skel-card-img shimmer"></div>
                <div class="skel-card-body">
                    <div class="skel-line lg shimmer"></div>
                    <div class="skel-line sm shimmer"></div>
                </div>
            </div>
        </div>
    </div>
</template>
