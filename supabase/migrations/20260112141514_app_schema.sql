-- ============================================================================
-- Migration: Application Schema
-- Created: 2026-01-12 14:15:14
-- 
-- Purpose:
--   Defines the application-level schema for Elytra:
--   - User profiles (linked to Supabase Auth)
--   - Workspaces (multi-tenant containers)
--   - Workspace permissions (role-based access control)
--   - RLS policies and triggers for automatic behavior
--
-- This is separate from the CPython object model schema, which is defined
-- in later migrations. This migration establishes the "app infrastructure"
-- that users interact with directly.
-- ============================================================================

-- 1. Profiles (Users) Table with Soft Delete
create table public.profiles (
  id uuid references auth.users on delete cascade not null primary key,
  updated_at timestamp with time zone,
  deleted_at timestamp with time zone, -- Added for soft delete
  username text unique,
  full_name text,
  avatar_url text,

  constraint username_length check (char_length(username) >= 3)
);

-- 2. Workspaces Table with Soft Delete
create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  created_at timestamp with time zone default now() not null,
  deleted_at timestamp with time zone, -- Added for soft delete
  name text not null,
  slug text unique,
  
  constraint name_length check (char_length(name) >= 1)
);

-- 3. Workspace Permissions
create table public.workspace_permissions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamp with time zone default now() not null,
  workspace_id uuid references public.workspaces(id) on delete cascade not null,
  user_id uuid references public.profiles(id) on delete cascade not null,
  role text not null check (role in ('owner', 'admin', 'member', 'viewer')),

  unique(workspace_id, user_id)
);

-- 4. Enable RLS
alter table public.profiles enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_permissions enable row level security;

-- 5. Profiles RLS Policies
create policy "Public profiles are viewable by everyone if not deleted." on public.profiles
  for select using (deleted_at is null);

create policy "Users can insert their own profile." on public.profiles
  for insert with check (auth.uid() = id);

create policy "Users can update own profile if not deleted." on public.profiles
  for update using (auth.uid() = id and deleted_at is null);

-- 6. Workspaces RLS Policies
create policy "Users can view workspaces they have access to and are not deleted." on public.workspaces
  for select using (
    deleted_at is null and
    exists (
      select 1 from public.workspace_permissions
      where workspace_id = public.workspaces.id and user_id = auth.uid()
    )
  );

create policy "Anyone can create a workspace." on public.workspaces
  for insert with check (true);

create policy "Owners and admins can update workspaces if not deleted." on public.workspaces
  for update using (
    deleted_at is null and
    exists (
      select 1 from public.workspace_permissions
      where workspace_id = public.workspaces.id 
      and user_id = auth.uid() 
      and role in ('owner', 'admin')
    )
  );

create policy "Owners can delete (soft) workspaces." on public.workspaces
  for delete using (
    exists (
      select 1 from public.workspace_permissions
      where workspace_id = public.workspaces.id 
      and user_id = auth.uid() 
      and role = 'owner'
    )
  );

-- 7. Workspace Permissions RLS Policies
create policy "Users can view permissions for workspaces they are in." on public.workspace_permissions
  for select using (
    exists (
      select 1 from public.workspace_permissions as wp
      where wp.workspace_id = public.workspace_permissions.workspace_id 
      and wp.user_id = auth.uid()
    )
  );

-- 8. Trigger Functions
-- Automatic Profile creation on signup
create function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'avatar_url');
  return new;
end;
$$ language plpgsql security definer;

-- Automatic Workspace Permission for creator
create function public.handle_workspace_creator()
returns trigger as $$
begin
  insert into public.workspace_permissions (workspace_id, user_id, role)
  values (new.id, auth.uid(), 'owner');
  return new;
end;
$$ language plpgsql security definer;

-- Automatic Soft Delete of workspace if no members left
create function public.handle_orphaned_workspace()
returns trigger as $$
begin
  if not exists (
    select 1 from public.workspace_permissions
    where workspace_id = old.workspace_id
  ) then
    update public.workspaces 
    set deleted_at = now() 
    where id = old.workspace_id and deleted_at is null;
  end if;
  return old;
end;
$$ language plpgsql security definer;

-- 9. Create Triggers
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create trigger on_workspace_created
  after insert on public.workspaces
  for each row execute procedure public.handle_workspace_creator();

create trigger on_permission_deleted
  after delete on public.workspace_permissions
  for each row execute procedure public.handle_orphaned_workspace();
