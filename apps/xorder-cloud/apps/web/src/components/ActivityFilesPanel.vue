<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'

const { t } = useI18n()

const props = defineProps({
    // When set, event counts and downloads are scoped to this tenant — on a
    // restaurant's page "312 events" must mean 312 of theirs.
    restaurantId: { type: [Number, String], default: null },
    // The day currently being viewed, so the row can show as selected.
    activeDate: { type: String, default: '' },
    // Collapsed by default on the busy audit screen; open on the quieter tab.
    startOpen: { type: Boolean, default: false },
})

const emit = defineEmits(['select'])

const files = ref([])
const open = ref(props.startOpen)
const loading = ref(true)

const params = computed(() => (props.restaurantId ? { restaurant_id: props.restaurantId } : {}))

async function load() {
    loading.value = true
    try {
        const { data } = await api.get('api/admin/audit-logs/files', { params: params.value })
        files.value = data.data
    } catch {
        // The event feed is the main content — a failure here must not blank it.
        files.value = []
    } finally {
        loading.value = false
    }
}

onMounted(load)
watch(() => props.restaurantId, load)

function download(date) {
    api.get(`api/admin/audit-logs/files/${date}`, { params: params.value, responseType: 'blob' })
        .then(({ data }) => {
            const url = URL.createObjectURL(data)
            const a = Object.assign(document.createElement('a'), { href: url, download: `activity-${date}.log` })
            a.click()
            URL.revokeObjectURL(url)
        })
}

function prettyBytes(n) {
    if (n < 1024) return `${n} B`
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`
    return `${(n / 1024 / 1024).toFixed(1)} MB`
}
</script>

<template>
    <div class="card p-4">
        <button class="files-head" @click="open = !open">
            <span class="flex items-center gap-2">
                <Icon name="items" :size="16" />
                <span class="h-card">{{ t('audit.files_title') }}</span>
                <span class="files-count">{{ files.length }}</span>
            </span>
            <span class="chev" :class="{ open }">›</span>
        </button>
        <p class="page-sub mt-1">{{ t('audit.files_sub') }}</p>

        <ul v-if="open" class="file-list">
            <li v-if="loading" class="py-3 text-sm" style="color:var(--muted)">{{ t('common.loading') }}</li>
            <li v-else-if="!files.length" class="py-3 text-sm" style="color:var(--muted)">{{ t('audit.files_none') }}</li>
            <li
                v-for="f in files"
                :key="f.date"
                class="file-row"
                :class="{ active: activeDate === f.date }"
            >
                <button class="file-main" @click="emit('select', f.date)">
                    <span class="file-name">{{ f.filename }}</span>
                    <span class="file-meta">
                        {{ t('audit.files_events', { n: f.events }) }} · {{ prettyBytes(f.bytes) }}
                    </span>
                </button>
                <button class="btn btn-ghost btn-sm" :title="t('audit.files_download')" @click="download(f.date)">
                    <Icon name="download" :size="14" />
                </button>
            </li>
        </ul>
    </div>
</template>

<style scoped>
.btn-sm { padding: 5px 11px; font-size: 12px; }

.files-head {
    display: flex; align-items: center; justify-content: space-between;
    width: 100%; background: none; border: 0; padding: 0; cursor: pointer; color: inherit;
}
.files-count {
    font-size: 12px; padding: 1px 8px; border-radius: 999px;
    background: var(--accent-soft, rgba(0, 0, 0, .06)); color: var(--muted);
}
.chev { transition: transform .15s ease; color: var(--muted); }
.chev.open { transform: rotate(90deg); }

.file-list { margin-top: 12px; border-top: 1px solid var(--line, rgba(0, 0, 0, .08)); }
.file-row {
    display: flex; align-items: center; gap: 8px;
    border-bottom: 1px solid var(--line, rgba(0, 0, 0, .06));
}
.file-row.active { background: var(--accent-soft, rgba(0, 0, 0, .04)); }
.file-main {
    flex: 1; display: flex; flex-direction: column; gap: 2px; align-items: flex-start;
    background: none; border: 0; padding: 9px 6px; cursor: pointer; color: inherit; text-align: start;
}
.file-name { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; }
.file-meta { font-size: 12px; color: var(--muted); }
</style>
