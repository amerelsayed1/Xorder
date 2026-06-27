<?php

namespace App\Models;

use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;

    protected $fillable = [
        'name',
        'email',
        'password',
        'role',
        'restaurant_id',
        'status',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'role' => RoleEnum::class,
            'status' => UserStatus::class,
        ];
    }

    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    public function isSuperAdmin(): bool
    {
        return $this->role === RoleEnum::SUPER_ADMIN;
    }

    public function isRestaurantAdmin(): bool
    {
        return $this->role === RoleEnum::RESTAURANT_ADMIN;
    }

    public function isActive(): bool
    {
        return $this->status === UserStatus::ACTIVE;
    }
}
