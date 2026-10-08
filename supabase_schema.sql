-- ==============================================================================
-- CivicConnect: Database Schema & Row Level Security (RLS)
-- Phase 4: Tables and Relationships
-- Phase 5: Row Level Security Configuration
-- ==============================================================================

-- 1. Enable UUID Extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Profiles Table
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    name TEXT,
    role TEXT NOT NULL DEFAULT 'citizen' CHECK (role IN ('citizen', 'admin')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Location Groups Table (Hotspot clusters)
CREATE TABLE IF NOT EXISTS public.location_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    center_latitude DOUBLE PRECISION NOT NULL,
    center_longitude DOUBLE PRECISION NOT NULL,
    complaint_count INTEGER NOT NULL DEFAULT 1,
    hotspot_level TEXT NOT NULL DEFAULT 'Normal' CHECK (hotspot_level IN ('Normal', 'Complaint Zone', 'High Activity Zone', 'Hotspot')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Complaints Table
CREATE TABLE IF NOT EXISTS public.complaints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    category TEXT NOT NULL CHECK (category IN ('Pothole', 'Garbage', 'Water Supply', 'Drainage', 'Streetlight', 'Road Damage', 'Public Area', 'Other')),
    description TEXT NOT NULL,
    image_url TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    address TEXT,
    severity TEXT NOT NULL DEFAULT 'MEDIUM' CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    priority_score DOUBLE PRECISION NOT NULL DEFAULT 0.0 CHECK (priority_score >= 0.0 AND priority_score <= 100.0),
    priority_level TEXT NOT NULL DEFAULT 'LOW' CHECK (priority_level IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'VERIFIED', 'WORK IN PROGRESS', 'SOLVED')),
    location_group_id UUID REFERENCES public.location_groups(id) ON DELETE SET NULL,
    related_complaint_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. Votes Table (Upvote / Downvote)
CREATE TABLE IF NOT EXISTS public.votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    complaint_id UUID NOT NULL REFERENCES public.complaints(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    vote_type TEXT NOT NULL CHECK (vote_type IN ('UPVOTE', 'DOWNVOTE')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_user_complaint_vote UNIQUE (complaint_id, user_id)
);

-- 6. Community Confirmations Table
CREATE TABLE IF NOT EXISTS public.complaint_confirmations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    complaint_id UUID NOT NULL REFERENCES public.complaints(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_user_complaint_confirmation UNIQUE (complaint_id, user_id)
);

-- 7. Complaint Updates Table (Status Timeline)
CREATE TABLE IF NOT EXISTS public.complaint_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    complaint_id UUID NOT NULL REFERENCES public.complaints(id) ON DELETE CASCADE,
    admin_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    old_status TEXT,
    new_status TEXT NOT NULL CHECK (new_status IN ('PENDING', 'VERIFIED', 'WORK IN PROGRESS', 'SOLVED')),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 8. Departments Table
CREATE TABLE IF NOT EXISTS public.departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    contact TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed Initial Departments
INSERT INTO public.departments (name, category, contact)
VALUES 
    ('Roads & Infrastructure Department', 'Pothole', 'roads@civicconnect.gov'),
    ('Roads & Infrastructure Department', 'Road Damage', 'roads@civicconnect.gov'),
    ('Solid Waste Management', 'Garbage', 'sanitation@civicconnect.gov'),
    ('Water Supply & Sewerage Board', 'Water Supply', 'water@civicconnect.gov'),
    ('Water Supply & Sewerage Board', 'Drainage', 'water@civicconnect.gov'),
    ('Electricity & Public Lighting', 'Streetlight', 'lighting@civicconnect.gov'),
    ('Public Works Department', 'Public Area', 'pwd@civicconnect.gov'),
    ('General Grievance Cell', 'Other', 'grievance@civicconnect.gov')
ON CONFLICT DO NOTHING;

-- 9. Automatic Profile Creation on User Signup Trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'role', 'citizen')
  )
  ON CONFLICT (id) DO UPDATE
  SET email = EXCLUDED.email;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 10. Helper function: is_admin() based securely on profiles.role
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==============================================================================
-- PHASE 5: ROW LEVEL SECURITY (RLS)
-- ==============================================================================

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaint_confirmations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaint_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.location_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

-- Profiles Policies
DROP POLICY IF EXISTS "Profiles are readable by authenticated users" ON public.profiles;
CREATE POLICY "Profiles are readable by authenticated users"
ON public.profiles FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
ON public.profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id);

-- Complaints Policies
DROP POLICY IF EXISTS "Complaints are readable by authenticated users" ON public.complaints;
CREATE POLICY "Complaints are readable by authenticated users"
ON public.complaints FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Authenticated users can submit complaints" ON public.complaints;
CREATE POLICY "Authenticated users can submit complaints"
ON public.complaints FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own complaints or admins can update any complaint" ON public.complaints;
CREATE POLICY "Users can update own complaints or admins can update any complaint"
ON public.complaints FOR UPDATE
TO authenticated
USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "Users can delete own complaints or admins can delete any complaint" ON public.complaints;
CREATE POLICY "Users can delete own complaints or admins can delete any complaint"
ON public.complaints FOR DELETE
TO authenticated
USING (auth.uid() = user_id OR public.is_admin());

-- Votes Policies
DROP POLICY IF EXISTS "Votes are readable by authenticated users" ON public.votes;
CREATE POLICY "Votes are readable by authenticated users"
ON public.votes FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Users can cast their own vote" ON public.votes;
CREATE POLICY "Users can cast their own vote"
ON public.votes FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can change their own vote" ON public.votes;
CREATE POLICY "Users can change their own vote"
ON public.votes FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own vote" ON public.votes;
CREATE POLICY "Users can delete their own vote"
ON public.votes FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

-- Confirmations Policies
DROP POLICY IF EXISTS "Confirmations are readable by authenticated users" ON public.complaint_confirmations;
CREATE POLICY "Confirmations are readable by authenticated users"
ON public.complaint_confirmations FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Users can confirm a complaint once" ON public.complaint_confirmations;
CREATE POLICY "Users can confirm a complaint once"
ON public.complaint_confirmations FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can remove their confirmation" ON public.complaint_confirmations;
CREATE POLICY "Users can remove their confirmation"
ON public.complaint_confirmations FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

-- Complaint Updates Policies (Status Timeline)
DROP POLICY IF EXISTS "Updates timeline is readable by authenticated users" ON public.complaint_updates;
CREATE POLICY "Updates timeline is readable by authenticated users"
ON public.complaint_updates FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Only admins can record status updates" ON public.complaint_updates;
CREATE POLICY "Only admins can record status updates"
ON public.complaint_updates FOR INSERT
TO authenticated
WITH CHECK (public.is_admin());

-- Location Groups Policies
DROP POLICY IF EXISTS "Location groups are readable by authenticated users" ON public.location_groups;
CREATE POLICY "Location groups are readable by authenticated users"
ON public.location_groups FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Authenticated users and admins can create/update location groups" ON public.location_groups;
CREATE POLICY "Authenticated users and admins can create/update location groups"
ON public.location_groups FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- Departments Policies
DROP POLICY IF EXISTS "Departments are readable by authenticated users" ON public.departments;
CREATE POLICY "Departments are readable by authenticated users"
ON public.departments FOR SELECT
TO authenticated
USING (true);

-- ==============================================================================
-- STORAGE BUCKET: complaint-images
-- ==============================================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('complaint-images', 'complaint-images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Storage RLS Policies
DROP POLICY IF EXISTS "Public access to complaint images" ON storage.objects;
CREATE POLICY "Public access to complaint images"
ON storage.objects FOR SELECT
USING (bucket_id = 'complaint-images');

DROP POLICY IF EXISTS "Authenticated users can upload complaint images" ON storage.objects;
CREATE POLICY "Authenticated users can upload complaint images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'complaint-images');

