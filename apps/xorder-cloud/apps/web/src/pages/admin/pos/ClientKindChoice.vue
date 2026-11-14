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
    <div class="max-w-3xl space-y-6">
        <RouterLink :to="{ name: 'admin.licences' }" class="back-link">{{ backArrow }} {{ t('common.back') }}</RouterLink>

        <div>
            <h1 class="page-title">{{ t('licence.new_client') }}</h1>
            <p class="page-sub" style="color:var(--body)">{{ t('licence.new_client_sub') }}</p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <RouterLink :to="{ name: 'admin.restaurants.create' }" class="card kind-card">
                <div class="flex items-center gap-3">
                    <span class="stat-ico"><Icon name="globe" :size="20" /></span>
                    <h2 class="h-card flex-1 min-w-0">{{ t('licence.kind.cloud') }}</h2>
                    <i class="pi pi-arrow-right kind-go" aria-hidden="true" />
                </div>
                <p class="text-sm" style="color:var(--body)">{{ t('licence.kind.cloud_blurb') }}</p>
                <ul class="kind-list">
                    <li v-for="line in ['cloud_1', 'cloud_2', 'cloud_3']" :key="line">
                        <i class="pi pi-check" aria-hidden="true" />
                        <span>{{ t('licence.kind.' + line) }}</span>
                    </li>
                </ul>
            </RouterLink>

            <RouterLink :to="{ name: 'admin.licences.offline' }" class="card kind-card">
                <div class="flex items-center gap-3">
                    <span class="stat-ico"><Icon name="building" :size="20" /></span>
                    <h2 class="h-card flex-1 min-w-0">{{ t('licence.kind.offline') }}</h2>
                    <i class="pi pi-arrow-right kind-go" aria-hidden="true" />
                </div>
                <p class="text-sm" style="color:var(--body)">{{ t('licence.kind.offline_blurb') }}</p>
                <ul class="kind-list">
                    <li v-for="line in ['offline_1', 'offline_2', 'offline_3']" :key="line">
                        <i class="pi pi-check" aria-hidden="true" />
                        <span>{{ t('licence.kind.' + line) }}</span>
                    </li>
                </ul>
            </RouterLink>
        </div>

        <!-- The third case, and deliberately not a card: an existing cloud
             tenant that needs an extra or replacement licence. It creates no
             client at all, so it does not belong beside the two that do. -->
        <div class="note">
            <Icon name="info" :size="18" class="note-ico" />
            <p class="text-sm" style="color:var(--body)">
                {{ t('licence.existing_client_note') }}
                <RouterLink :to="{ name: 'admin.licences.create' }" class="note-link">{{ t('licence.issue_to_existing') }}</RouterLink>
            </p>
        </div>
    </div>
</template>

<style scoped>
.back-link { display: inline-flex; align-items: center; min-height: 44px; font-size: 14px; font-weight: 500; color: var(--body); }
.back-link:hover { color: var(--ink); }

.kind-card {
    display: flex; flex-direction: column; gap: 14px; padding: 22px;
    transition: border-color .15s ease, box-shadow .15s ease;
}
.kind-card:hover { border-color: var(--accent); box-shadow: 0 2px 10px rgba(0, 0, 0, .05); }
.kind-card:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.kind-go { color: var(--body); font-size: 14px; transition: transform .15s ease, color .15s ease; }
.kind-card:hover .kind-go { color: var(--p-primary-700); transform: translateX(3px); }
/* Scoped, not `:global(...)`: Vue's scoped compiler drops everything after a
   `:global(x)` prefix, leaving a bare `[dir=rtl]` rule that mirrored the whole
   page in Arabic. The scope attribute lands on `.kind-go`, which is what we
   want, and `[dir=rtl]` stays an ordinary ancestor, as on the other pages. */
[dir=rtl] .kind-go { transform: scaleX(-1); }
[dir=rtl] .kind-card:hover .kind-go { transform: scaleX(-1) translateX(3px); }

.kind-list { list-style: none; margin: 0; padding: 12px 0 0; border-top: 1px solid var(--line);
    display: flex; flex-direction: column; gap: 8px; }
.kind-list li { display: flex; align-items: flex-start; gap: 9px; font-size: 14px; line-height: 1.45; color: var(--body); }
.kind-list .pi { font-size: 11px; margin-top: 5px; color: var(--green); flex: none; }

.note { display: flex; align-items: flex-start; gap: 12px; padding: 14px 16px; border-radius: 12px;
    background: var(--card); border: 1px solid var(--line); }
.note-ico { color: var(--body); flex: none; margin-top: 1px; }
.note-link { font-weight: 600; color: var(--p-primary-700); }
.note-link:hover { text-decoration: underline; }
</style>
