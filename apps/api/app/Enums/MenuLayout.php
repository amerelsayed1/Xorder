<?php

namespace App\Enums;

/**
 * How the public menu presents its items. Chosen per-restaurant by the Super
 * Admin; the customer menu app renders the matching layout.
 *  - PHOTO:     image cards (the default look).
 *  - TEXT_GRID: the same card grid without photos — clean text tiles.
 *  - TEXT_LIST: a classic printed-menu list (dot leaders, no photos).
 */
enum MenuLayout: string
{
    case PHOTO = 'photo';
    case TEXT_GRID = 'text-grid';
    case TEXT_LIST = 'text-list';
}
