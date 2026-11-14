import { ref } from 'vue'
import api, { ensureCsrf } from '@xorder/api-client/api.js'

/**
 * Composable for image uploads - single source of truth for all image upload operations
 * Handles CSRF, API calls, error handling, and loading states
 */
export function useImageUpload() {
  const uploading = ref(false)
  const error = ref('')

  /**
   * Upload an image file and return the URL
   * @param {File} file - The image file to upload
   * @param {string} folder - The folder to store the image in (logos, covers, categories, items, uploads)
   * @returns {Promise<string>} - The URL of the uploaded image
   */
  async function uploadFile(file, folder = 'uploads') {
    error.value = ''
    uploading.value = true

    try {
      await ensureCsrf()
      const formData = new FormData()
      formData.append('image', file)
      formData.append('folder', folder)

      const { data } = await api.post('api/uploads/image', formData)
      return data.data.url
    } catch (err) {
      error.value = err.response?.data?.message || 'Upload failed'
      throw err
    } finally {
      uploading.value = false
    }
  }

  /**
   * Validate an image URL
   * @param {string} url - The URL to validate
   * @returns {boolean} - Whether the URL is valid
   */
  function validateImageUrl(url) {
    if (!url || !url.trim()) {
      error.value = 'Please enter a valid URL'
      return false
    }

    try {
      new URL(url)
      error.value = ''
      return true
    } catch {
      error.value = 'Invalid URL format'
      return false
    }
  }

  /**
   * Clear any errors
   */
  function clearError() {
    error.value = ''
  }

  return {
    uploading,
    error,
    uploadFile,
    validateImageUrl,
    clearError,
  }
}
