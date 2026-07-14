import { ref, reactive } from 'vue'

export function useOrder() {
    const orderDialog = ref(false)
    const submittingOrder = ref(false)
    const orderSuccess = ref(false)
    const lastOrderUrl = ref('')
    const lastOrderCode = ref('')
    const customer = reactive({})
    const orderErrors = reactive({})

    /**
     * Build the WhatsApp order lines from the cart. Each line shows the
     * localized item name, its selected options and the line total, so the
     * restaurant can prepare the order without asking follow-up questions.
     */
    function buildOrderData(cart, restaurant, cartCount, cartTotal, money, localize, getLineOptions, orderTypeLabel = '') {
        const lines = cart.map((line) => {
            const options = getLineOptions(line, localize)
            const optionsPart = options.length ? ` (${options.join(' + ')})` : ''
            const notePart = line.note ? `\n  ✎ ${line.note}` : ''
            return `${line.qty}x ${localize(line.ref)}${optionsPart} — ${money(line.qty * line.price)}${notePart}`
        }).join('\n')

        return {
            restaurant: localize(restaurant),
            items: lines,
            total: money(cartTotal),
            customer: customer.name || '',
            phone: customer.phone || '',
            note: customer.note || '',
            orderType: orderTypeLabel || '',
        }
    }

    /**
     * Open WhatsApp with the prepared order. Returns the URL so the caller
     * can offer a "re-open" action — popup blockers and missing WhatsApp
     * installs are common enough that the customer needs a retry path.
     */
    function sendToWhatsApp(orderData, waDigits, t) {
        const detailLines = [
            `*${t('total')}:* ${orderData.total}`,
            orderData.orderType ? `*${t('order_type')}:* ${orderData.orderType}` : null,
            orderData.customer ? `*${t('f_name')}:* ${orderData.customer}` : null,
            orderData.phone ? `*${t('f_phone')}:* ${orderData.phone}` : null,
            orderData.note ? `*${t('f_note')}:* ${orderData.note}` : null,
        ].filter(Boolean).join('\n')

        const msg = `*${t('new_order')}*\n\n${orderData.items}\n\n${detailLines}`
        const url = `https://wa.me/${waDigits}?text=${encodeURIComponent(msg)}`
        lastOrderUrl.value = url

        // Popup blocked → navigate the current tab instead of failing silently.
        const win = window.open(url, '_blank')
        if (!win) window.location.href = url

        return url
    }

    function resetCustomerForm() {
        Object.keys(customer).forEach(k => delete customer[k])
        Object.keys(orderErrors).forEach(k => delete orderErrors[k])
    }

    return {
        orderDialog,
        submittingOrder,
        orderSuccess,
        lastOrderUrl,
        lastOrderCode,
        customer,
        orderErrors,
        buildOrderData,
        sendToWhatsApp,
        resetCustomerForm,
    }
}
