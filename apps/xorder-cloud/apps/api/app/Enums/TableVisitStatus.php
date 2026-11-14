<?php

namespace App\Enums;

enum TableVisitStatus: string
{
    case OPEN = 'OPEN';
    case CLOSED = 'CLOSED';
    case CANCELLED = 'CANCELLED';
}
