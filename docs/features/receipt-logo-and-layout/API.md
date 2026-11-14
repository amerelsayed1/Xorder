# API — receipt-logo-and-layout

None. This change is inside the POS app: no endpoint, request, response or `POS-BE-xxx` contract item is added or changed. The logo is read from the till's own database (`pos_restaurants.logo_bytes`, written by XORD-021's own sync); nothing new is sent to or received from the cloud.
