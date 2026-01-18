-- =====================================================
-- Migration: Core Application Schema
-- Description: User profiles, workspaces, and permissions
-- =====================================================

-------------------------------------------------------
-- 1. Profiles (Users) Table with Soft Delete
-------------------------------------------------------
CREATE TABLE public.profiles (
  id uuid REFERENCES auth.users ON DELETE CASCADE NOT NULL PRIMARY KEY,
  updated_at timestamp with time zone,
  deleted_at timestamp with time zone, -- Soft delete
  username text UNIQUE,
  full_name text,
  avatar_url text,

  CONSTRAINT username_length CHECK (char_length(username) >= 3)
);

-------------------------------------------------------
-- 2. Workspaces Table with Soft Delete
-------------------------------------------------------
CREATE TABLE public.workspaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  deleted_at timestamp with time zone, -- Soft delete
  name text NOT NULL,
  slug text UNIQUE,
  
  CONSTRAINT name_length CHECK (char_length(name) >= 1)
);

-------------------------------------------------------
-- 3. Workspace Permissions
-------------------------------------------------------
CREATE TABLE public.workspace_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  workspace_id uuid REFERENCES public.workspaces(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  role text NOT NULL CHECK (role IN ('owner', 'admin', 'member', 'viewer')),

  UNIQUE(workspace_id, user_id)
);

-------------------------------------------------------
-- 4. Enable Row Level Security
-------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_permissions ENABLE ROW LEVEL SECURITY;

-------------------------------------------------------
-- 5. RLS Policies: Profiles
-------------------------------------------------------
CREATE POLICY "Public profiles are viewable by everyone if not deleted." 
ON public.profiles FOR SELECT 
USING (deleted_at IS NULL);

CREATE POLICY "Users can insert their own profile." 
ON public.profiles FOR INSERT 
WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile if not deleted." 
ON public.profiles FOR UPDATE 
USING (auth.uid() = id AND deleted_at IS NULL);

-------------------------------------------------------
-- 6. RLS Policies: Workspaces
-------------------------------------------------------
CREATE POLICY "Users can view workspaces they have access to and are not deleted." 
ON public.workspaces FOR SELECT 
USING (
  deleted_at IS NULL AND
  EXISTS (
    SELECT 1 FROM public.workspace_permissions
    WHERE workspace_id = public.workspaces.id AND user_id = auth.uid()
  )
);

CREATE POLICY "Anyone can create a workspace." 
ON public.workspaces FOR INSERT 
WITH CHECK (true);

CREATE POLICY "Owners and admins can update workspaces if not deleted." 
ON public.workspaces FOR UPDATE 
USING (
  deleted_at IS NULL AND
  EXISTS (
    SELECT 1 FROM public.workspace_permissions
    WHERE workspace_id = public.workspaces.id 
    AND user_id = auth.uid() 
    AND role IN ('owner', 'admin')
  )
);

CREATE POLICY "Owners can delete (soft) workspaces." 
ON public.workspaces FOR DELETE 
USING (
  EXISTS (
    SELECT 1 FROM public.workspace_permissions
    WHERE workspace_id = public.workspaces.id 
    AND user_id = auth.uid() 
    AND role = 'owner'
  )
);

-------------------------------------------------------
-- 7. RLS Policies: Workspace Permissions
-------------------------------------------------------
CREATE POLICY "Users can view permissions for workspaces they are in." 
ON public.workspace_permissions FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM public.workspace_permissions AS wp
    WHERE wp.workspace_id = public.workspace_permissions.workspace_id 
    AND wp.user_id = auth.uid()
  )
);

-------------------------------------------------------
-- 8. Trigger Functions
-------------------------------------------------------

-- Automatic Profile creation on signup
CREATE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, avatar_url)
  VALUES (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'avatar_url');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Automatic Workspace Permission for creator
CREATE FUNCTION public.handle_workspace_creator()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.workspace_permissions (workspace_id, user_id, role)
  VALUES (new.id, auth.uid(), 'owner');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Automatic Soft Delete of workspace if no members left
CREATE FUNCTION public.handle_orphaned_workspace()
RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_permissions
    WHERE workspace_id = old.workspace_id
  ) THEN
    UPDATE public.workspaces 
    SET deleted_at = now() 
    WHERE id = old.workspace_id AND deleted_at IS NULL;
  END IF;
  RETURN old;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-------------------------------------------------------
-- 9. Create Triggers
-------------------------------------------------------
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

CREATE TRIGGER on_workspace_created
  AFTER INSERT ON public.workspaces
  FOR EACH ROW EXECUTE PROCEDURE public.handle_workspace_creator();

CREATE TRIGGER on_permission_deleted
  AFTER DELETE ON public.workspace_permissions
  FOR EACH ROW EXECUTE PROCEDURE public.handle_orphaned_workspace();
