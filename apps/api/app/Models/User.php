<?php

namespace App\Models;

use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use App\Models\Concerns\Auditable;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use Auditable, HasApiTokens, HasFactory, Notifiable;

    // Never surface credential columns in audit change diffs.
    protected array $auditExclude = ['password', 'remember_token', 'email_verified_at'];

    // `role` and `restaurant_id` are deliberately NOT mass-assignable: they are
    // the privilege/tenant boundary and must only ever be set explicitly in
    // trusted provisioning code, never from request input. This prevents a
    // future `User::create($request->all())`/`update()` from letting a caller
    // self-promote to SUPER_ADMIN or hop tenants.
    protected $fillable = [
        'name',
        'username',
        'email',
        'password',
        'status',
    ];

    /** Usernames are case-insensitive: always stored lowercase + trimmed. */
    protected function username(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => $value === null ? null : mb_strtolower(trim($value)),
        );
    }

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'password_changed_at' => 'datetime',
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
