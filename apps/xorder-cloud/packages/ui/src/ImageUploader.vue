<script setup>
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useImageUpload } from './composables/useImageUpload'

const props = defineProps({
    modelValue: { type: String, default: '' },
    folder: { type: String, default: 'uploads' },
    label: { type: String, default: '' },
    // Read-only mode (e.g. lapsed subscription): block replace/clear/upload/URL.
    disabled: { type: Boolean, default: false },
})

const emit = defineEmits(['update:modelValue'])
const { t } = useI18n()
const { uploading, error, uploadFile, validateImageUrl, clearError } = useImageUpload()

const urlInput = ref('')
const showUrlInput = ref(false)

async function onChange(e) {
    const file = e.target.files?.[0]
    if (!file) return

    clearError()
    try {
        const url = await uploadFile(file, props.folder)
        emit('update:modelValue', url)
    } catch (err) {
        // Error is already set in the composable
    } finally {
        e.target.value = '' // let the same file be re-picked after a failure
    }
}

function addUrl() {
    if (!validateImageUrl(urlInput.value)) return

    emit('update:modelValue', urlInput.value.trim())
    urlInput.value = ''
    showUrlInput.value = false
}

function cancelUrl() {
    urlInput.value = ''
    showUrlInput.value = false
    clearError()
}

function clearImage() {
    emit('update:modelValue', '')
    clearError()
}
</script>

<template>
    <div>
        <span class="label">{{ label || t('common.image') }}</span>
        <div class="mt-1.5">
            <!-- Filled: preview + actions -->
            <div v-if="modelValue" class="iu-preview">
                <img :src="modelValue" alt="" class="iu-thumb" />
                <div v-if="!disabled" class="iu-preview-actions">
                    <label class="iu-btn" :class="{ 'is-uploading': uploading }">
                        <span v-if="uploading" class="iu-spinner"></span>
                        {{ uploading ? t('common.loading') : t('common.replace') }}
                        <input type="file" accept="image/*" class="iu-file" @change="onChange" :disabled="uploading" />
                    </label>
                    <button type="button" @click="clearImage" class="iu-btn iu-btn-danger">{{ t('common.clear') }}</button>
                </div>
            </div>

            <!-- Empty: solid dropzone + optional URL entry -->
            <template v-else-if="disabled">
                <div class="iu-drop iu-drop--disabled">{{ t('common.image') }}</div>
            </template>
            <template v-else>
                <label class="iu-drop" :class="{ 'is-uploading': uploading }">
                    <span class="iu-icon">
                        <span v-if="uploading" class="iu-spinner"></span>
                        <svg v-else viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" width="20" height="20">
                            <path d="M12 16V4" /><path d="m7 9 5-5 5 5" /><path d="M5 20h14" />
                        </svg>
                    </span>
                    <span class="iu-drop-text">
                        <strong>{{ uploading ? t('common.loading') : t('common.upload') }}</strong>
                        <small>JPG · PNG · GIF</small>
                    </span>
                    <input type="file" accept="image/*" class="iu-file" @change="onChange" :disabled="uploading" />
                </label>

                <button v-if="!showUrlInput" type="button" class="iu-link" @click="showUrlInput = true">
                    {{ t('common.paste_url') }}
                </button>

                <div v-else class="iu-url">
                    <input
                        v-model="urlInput"
                        type="url"
                        placeholder="https://example.com/image.jpg"
                        class="input w-full text-sm"
                        @keyup.enter="addUrl"
                    />
                    <div class="iu-url-actions">
                        <button type="button" @click="addUrl" class="btn btn-accent btn-sm">{{ t('common.save') }}</button>
                        <button type="button" @click="cancelUrl" class="btn btn-ghost btn-sm">{{ t('common.cancel') }}</button>
                    </div>
                </div>
            </template>
        </div>
        <p v-if="error" class="text-xs mt-2" style="color:#c0392b">{{ error }}</p>
    </div>
</template>

<style scoped>
.iu-file { position: absolute; width: 1px; height: 1px; opacity: 0; pointer-events: none; }

/* Empty-state upload tile — solid, theme-aware, no dashed border. */
.iu-drop {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 13px 14px;
    border: 1px solid var(--line);
    border-radius: 12px;
    background: var(--page);
    cursor: pointer;
    transition: border-color .15s, background .15s, box-shadow .15s;
}
.iu-drop:hover {
    border-color: var(--accent);
    background: var(--accent-soft, color-mix(in srgb, var(--accent, #f59e0b) 8%, transparent));
}
.iu-icon {
    flex: none;
    width: 40px;
    height: 40px;
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--accent-soft, color-mix(in srgb, var(--accent, #f59e0b) 14%, transparent));
    color: var(--accent, #f59e0b);
}
.iu-drop-text { display: flex; flex-direction: column; line-height: 1.35; }
.iu-drop-text strong { color: var(--ink); font-size: 14px; font-weight: 600; }
.iu-drop-text small { color: var(--muted); font-size: 12px; }

.iu-link {
    margin-top: 8px;
    display: inline-block;
    font-size: 13px;
    font-weight: 500;
    color: var(--accent, #f59e0b);
    background: none;
    border: 0;
    padding: 2px 0;
    cursor: pointer;
}
.iu-link:hover { text-decoration: underline; }

.iu-url { margin-top: 10px; display: flex; flex-direction: column; gap: 8px; }
.iu-url-actions { display: flex; gap: 8px; }

/* Filled-state preview */
.iu-preview { display: flex; align-items: center; gap: 14px; }
.iu-thumb {
    width: 72px;
    height: 72px;
    border-radius: 12px;
    object-fit: cover;
    border: 1px solid var(--line);
    flex: none;
}
.iu-preview-actions { display: flex; gap: 8px; flex-wrap: wrap; }
.iu-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 13px;
    font-weight: 500;
    padding: 7px 13px;
    border-radius: 9px;
    border: 1px solid var(--line);
    background: var(--card);
    color: var(--body);
    cursor: pointer;
    transition: border-color .15s, color .15s, background .15s;
}
.iu-btn:hover { border-color: var(--accent); color: var(--accent); }
.iu-btn-danger:hover { border-color: var(--red, #dc2626); color: var(--red, #dc2626); }

/* Self-contained spinner so upload progress is obvious without depending on
   Tailwind's animate-spin being generated for this shared-package component. */
.iu-spinner {
    width: 14px;
    height: 14px;
    border: 2px solid color-mix(in srgb, var(--accent, #f59e0b) 30%, transparent);
    border-top-color: var(--accent, #f59e0b);
    border-radius: 50%;
    display: inline-block;
    animation: iu-spin .6s linear infinite;
}
.is-uploading { pointer-events: none; opacity: .75; }
@keyframes iu-spin { to { transform: rotate(360deg); } }
</style>
