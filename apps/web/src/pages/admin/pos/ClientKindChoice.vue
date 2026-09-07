<script setup>
import { computed } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import Icon from '@xorder/ui/Icon.vue'

const { t, locale } = useI18n()
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')
</script>

<!--
    The fork every new client starts at.

    The two answers are not two shapes of the same record — they are two
    different records, and choosing between them later is expensive. A CLOUD
    client is a tenant we host: they get a restaurant, an admin login, a
    subscription, and a licence minted with all of it. An OFFLINE client gets a
    licence and nothing else, because their database lives in their building and
    a tenant row here would describe a business we do not run.

    Asked up front rather than inferred from a checkbox on a long form, because
    everything downstream — what is created, what is synced, what an operator is
    even shown — follows from it.
-->
<template>
    <div class="max-w-3xl space-y-5">
        <RouterLink :to="{ name: 'admin.licences' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>

        <div>
            <h1 class="page-title">{{ t('licence.new_client') }}</h1>
            <p class="page-sub">{{ t('licence.new_client_sub') }}</p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <RouterLink :to="{ name: 'admin.restaurants.create' }" class="card p-6 kind-card">
                <div class="flex items-center gap-2.5 mb-2">
                    <Icon name="globe" :size="18" style="color:var(--accent)" />
                    <h2 class="font-semibold" style="color:var(--ink)">{{ t('licence.kind.cloud') }}</h2>
                </div>
                <p class="text-sm mb-3" style="color:var(--body)">{{ t('licence.kind.cloud_blurb') }}</p>
                <ul class="text-xs space-y-1" style="color:var(--muted)">
                    <li v-for="line in ['cloud_1', 'cloud_2', 'cloud_3']" :key="line">· {{ t('licence.kind.' + line) }}</li>
                </ul>
            </RouterLink>

            <RouterLink :to="{ name: 'admin.licences.offline' }" class="card p-6 kind-card">
                <div class="flex items-center gap-2.5 mb-2">
                    <Icon name="building" :size="18" style="color:var(--accent)" />
                    <h2 class="font-semibold" style="color:var(--ink)">{{ t('licence.kind.offline') }}</h2>
                </div>
                <p class="text-sm mb-3" style="color:var(--body)">{{ t('licence.kind.offline_blurb') }}</p>
                <ul class="text-xs space-y-1" style="color:var(--muted)">
                    <li v-for="line in ['offline_1', 'offline_2', 'offline_3']" :key="line">· {{ t('licence.kind.' + line) }}</li>
                </ul>
            </RouterLink>
        </div>

        <!-- The third case, and deliberately not a card: an existing cloud
             tenant that needs an extra or replacement licence. It creates no
             client at all, so it does not belong beside the two that do. -->
        <div class="card p-4 flex items-start gap-3" style="border-inline-start:3px solid var(--line)">
            <Icon name="info" :size="18" style="color:var(--muted);flex:none;margin-top:1px" />
            <p class="text-sm" style="color:var(--body)">
                {{ t('licence.existing_client_note') }}
                <RouterLink :to="{ name: 'admin.licences.create' }" style="color:var(--accent)">{{ t('licence.issue_to_existing') }}</RouterLink>
            </p>
        </div>
    </div>
</template>

<style scoped>
.kind-card {
    display: block;
    transition: border-color .12s ease, transform .12s ease;
}
.kind-card:hover {
    border-color: var(--accent);
    transform: translateY(-1px);
}
</style>
