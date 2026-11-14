import { ref, reactive, computed } from 'vue'

export function useUserInfo() {
    const userInfoDialog = ref(false)
    const isEditing = ref(false)
    const userInfo = reactive({})
    const editForm = reactive({})
    const saveSuccess = ref(false)

    const hasUserInfo = computed(() => !!userInfo.name)
    const initials = computed(() => {
        if (!userInfo.name) return ''
        return userInfo.name.split(' ').map(n => n[0]).join('').toUpperCase()
    })

    function loadUserInfo() {
        const stored = localStorage.getItem('xorder_user_info')
        if (stored) {
            const data = JSON.parse(stored)
            Object.assign(userInfo, data)
        }
    }

    function saveUserInfo() {
        Object.assign(userInfo, editForm)
        localStorage.setItem('xorder_user_info', JSON.stringify(userInfo))
        isEditing.value = false
        saveSuccess.value = true
        setTimeout(() => (saveSuccess.value = false), 2000)
    }

    function enterEditMode() {
        Object.assign(editForm, userInfo)
        isEditing.value = true
    }

    function cancelEdit() {
        isEditing.value = false
        Object.keys(editForm).forEach(k => delete editForm[k])
    }

    function clearUserInfo() {
        Object.keys(userInfo).forEach(k => delete userInfo[k])
        localStorage.removeItem('xorder_user_info')
    }

    function openDialog() {
        loadUserInfo()
        userInfoDialog.value = true
    }

    function closeDialog() {
        userInfoDialog.value = false
        isEditing.value = false
    }

    return {
        userInfoDialog,
        isEditing,
        userInfo,
        editForm,
        saveSuccess,
        hasUserInfo,
        initials,
        loadUserInfo,
        saveUserInfo,
        enterEditMode,
        cancelEdit,
        clearUserInfo,
        openDialog,
        closeDialog,
    }
}
